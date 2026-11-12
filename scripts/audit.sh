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
printf 'Passed: %d, failed: %d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
