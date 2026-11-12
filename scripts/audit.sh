#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0

check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$description"
        ((PASS++))
    else
        printf '  [FAIL] %s (expected: %s, actual: %s)\n' "$description" "$expected" "$actual"
        ((FAIL++))
    fi
}

sshd_config=$(sudo sshd -T) || exit 1
ufw_status=$(sudo ufw status verbose) || exit 1

echo "[1] OpenSSH"
check "Root login disabled" no "$(awk '$1=="permitrootlogin"{print $2}' <<< "$sshd_config")"
check "Password authentication disabled" no "$(awk '$1=="passwordauthentication"{print $2}' <<< "$sshd_config")"
check "Only non-default SSH ports configured" yes "$(awk '$1=="port"{seen=1; if ($2==22) bad=1} END{print (seen && !bad) ? "yes" : "no"}' <<< "$sshd_config")"
check "MaxAuthTries is 3" 3 "$(awk '$1=="maxauthtries"{print $2}' <<< "$sshd_config")"
echo "[2] UFW"
check "Firewall active" active "$(awk '$1=="Status:"{print $2}' <<< "$ufw_status")"
check "Default incoming policy is deny" deny "$(awk '$1=="Default:" && $3=="(incoming),"{print $2}' <<< "$ufw_status")"
echo "[3] Local accounts"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Web server"
nginx_state=$(systemctl is-active nginx) || true
check "Nginx service active" active "$nginx_state"

nginx_config=invalid
if sudo nginx -t >/dev/null 2>&1; then nginx_config=valid; fi
check "Nginx configuration valid" valid "$nginx_config"

certificate=invalid
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "${CERT_MIN_SECONDS:-2592000}" >/dev/null 2>&1; then
    certificate=valid
fi
check "TLS certificate meets validity threshold" valid "$certificate"

site_permissions=invalid
if writable=$(find /var/www/devops-site -perm -o+w -print) && [[ -z "$writable" ]] &&
   key_mode=$(sudo stat -c '%a' /etc/ssl/private/devops.key) && [[ "$key_mode" == 600 ]]; then
    site_permissions=valid
fi
check "Site is not world-writable and TLS key mode is 600" valid "$site_permissions"
echo "[5] Containerization"
docker_state=$(systemctl is-active docker) || true
check "Docker service active" active "$docker_state"

db_health=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null) || db_health=unavailable
check "Database container healthy" healthy "$db_health"

ports=invalid
if listeners=$(ss -H -ltn) && awk '
    $4 == "127.0.0.1:5000" { app = 1; next }
    $4 ~ /:(5000|5432)$/ { unexpected = 1 }
    END { exit !(app && !unexpected) }
' <<< "$listeners"; then
    ports=valid
fi
check "App listens on loopback only and PostgreSQL is not published" valid "$ports"

env_mode=$(stat -c '%a' /home/devops/app/.env 2>/dev/null) || env_mode=unavailable
check "Compose environment file mode is 600" 600 "$env_mode"
printf 'Passed: %d, failed: %d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
