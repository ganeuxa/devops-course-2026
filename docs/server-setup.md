# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

VirtualBox 7.2, Ubuntu Server 24.04.5 LTS, 2048 МБ ОЗУ, 2 ядра, динамический VDI 25 ГБ. Исходная точка восстановления — снимок 01-clean-install.

## 2. Сетевые интерфейсы

- enp0s3, NAT, 10.0.2.15/24. Исходящий доступ в интернет.
- enp0s8, Host-only, DHCP, 192.168.56.102/24 при проверке. Адрес Windows на этом сегменте — 192.168.56.1. После восстановления проверьте адрес командой ip -brief address.

## 3. Проброс портов

Имя правила ssh, TCP, хост 127.0.0.1:2222. Гостевой порт исходно 22, после усиления SSH — 2222. В VirtualBox измените гостевой порт после проверки конфигурации sshd и запуска службы.

## 4. Учётные записи

student — исходная учётная запись с sudo. Создайте devops через sudo adduser devops и sudo usermod -aG sudo devops. Добавьте открытый ключ Windows из ~/.ssh/devops_vm.pub в /home/devops/.ssh/authorized_keys. Владелец каталога и файла — devops, права 700 и 600 соответственно. Проверьте вход с Windows перед отключением паролей.

В ~/.ssh/config на Windows задайте Host devops, HostName 127.0.0.1, Port 2222, User devops, IdentityFile ~/.ssh/devops_vm и IdentitiesOnly yes.

## 5. Служба SSH

Сохраните копию /etc/ssh/sshd_config в /etc/ssh/sshd_config.backup. Запишите в /etc/ssh/sshd_config.d/99-hardening.conf:

~~~text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
~~~

Если более ранний файл в sshd_config.d задаёт PasswordAuthentication yes, закомментируйте эту строку. Выполните sudo sshd -t и проверьте значения через sudo sshd -T. Сохраните текущую SSH-сессию, отключите sudo systemctl disable --now ssh.socket и включите sudo systemctl enable --now ssh.service. Перезапустите sudo systemctl restart ssh.service. Проверьте sudo ss -tlnp, перенастройте NAT и подтвердите вход командой ssh devops в отдельном терминале.

## 6. Межсетевой экран и имена

~~~bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw limit 2222/tcp
sudo ufw logging medium
sudo ufw status verbose
~~~

Проверьте доступ после включения UFW и после установки LIMIT. В гостевом /etc/hosts задайте 127.0.1.1 devops-vm.devops.local devops-vm и проверьте hostname -f. В Windows для доступа по имени добавьте в hosts запись с актуальным Host-only IP и именем devops.local, затем выполните ipconfig /flushdns и ssh -p 2222 devops@devops.local.

## 7. Снимки состояния

- 01-clean-install — Ubuntu Server и OpenSSH до изменения SSH.
- 02-keys-configured — после проверки входа по ключу.
- 03-ssh-hardened — после проверки порта 2222 и запрета входа под root и по паролю.

Для проверки конечного состояния запустите scripts/audit.sh на гостевом сервере.

## 8. Веб-сервер

Установите пакеты nginx и rsync. Создайте /var/www/devops-site с владельцем devops:devops и правами 755. Каталоги ресурса имеют права 755, файлы — 644.

Сформируйте сертификат на 365 дней с SAN devops.local. Закрытый ключ хранится на сервере.

~~~bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
~~~

Конфигурация /etc/nginx/sites-available/devops-site:

~~~nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    access_log /var/log/nginx/devops-site.access.log;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    server_name devops.local;
    root /var/www/devops-site;
    index index.html;
    location / {
        try_files $uri $uri/ =404;
    }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
~~~

Включите ресурс символьной ссылкой в /etc/nginx/sites-enabled и отключите ссылку default. После изменений выполните sudo nginx -t && sudo systemctl reload nginx. В UFW используются правила 80/tcp и 443/tcp.

Скопируйте открытый сертификат в ~/devops.crt через SSH. В рабочей копии выполните scripts/deploy.sh --dry-run и scripts/deploy.sh. Для проверки используйте curl --cacert ~/devops.crt https://devops.local. Снимок после настройки HTTPS — 04-nginx-https.

## 9. Контейнеризация

Docker Engine 29.9.3 установлен из официального APT-репозитория Docker для Ubuntu Noble. Используется плагин Compose v5.7.1. Учётная запись devops включена в группу docker.

С хоста синхронизируйте app/ с каталогом /home/devops/app. Файл .env исключён из Git, контекста сборки и синхронизации.

~~~bash
rsync -avz --delete --chmod=D755,F644 --exclude=.env -e 'ssh -o BatchMode=yes' app/ devops:app/
~~~

На сервере создайте /home/devops/app/.env с правами 600 при первом запуске. При восстановлении с сохранённым томом используйте исходные реквизиты базы.

~~~bash
cd ~/app
if [ ! -e .env ]; then
    umask 077
    password=$(openssl rand -hex 16)
    sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$password/" .env.example > .env
    unset password
fi
chmod 600 .env
docker compose up -d --build --wait
docker compose ps
~~~

Gunicorn слушает 5000 в контейнере. На сервере опубликован только 127.0.0.1:5000. PostgreSQL 16 использует сеть backend, имя db и том app_db_data. Порт 5432 доступен внутри сети Compose. Команда docker compose down сохраняет именованный том.

В HTTPS-блок /etc/nginx/sites-available/devops-site добавьте:

~~~nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
~~~

Примените sudo nginx -t && sudo systemctl reload nginx. Проверьте curl --cacert ~/devops.crt https://devops.local/app/health и HTTP 200 для статического ресурса /. Снимок проекта — 05-docker-compose.
