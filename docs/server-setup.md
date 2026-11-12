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
