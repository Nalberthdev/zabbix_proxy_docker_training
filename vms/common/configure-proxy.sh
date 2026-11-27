#!/bin/bash
# Ajusta o zabbix_proxy.conf instalado pelo pacote, como o time faria na
# instalacao de um proxy novo. Roda so no build da imagem.
set -e
CONF=/etc/zabbix/zabbix_proxy.conf
NAME=$1   # Hostname do proxy (igual ao cadastrado no frontend)
MODE=$2   # 0 = ativo, 1 = passivo

sed -i \
    -e "s|^Server=.*|Server=zabbix-server|" \
    -e "s|^Hostname=.*|Hostname=${NAME}|" \
    -e "s|^DBName=.*|DBName=/var/lib/zabbix/zabbix_proxy.db|" \
    -e "s|^DBUser=|# DBUser=|" \
    "$CONF"
sed -i "/^# ProxyMode=/a ProxyMode=${MODE}" "$CONF"
grep -q "^ProxyMode=" "$CONF" || echo "ProxyMode=${MODE}" >> "$CONF"

mkdir -p /var/lib/zabbix /var/lib/lab-systemctl
chown zabbix:zabbix /var/lib/zabbix
touch /var/lib/lab-systemctl/zabbix-proxy.enabled

# Usuario de operacao (o "seu" usuario no servidor). Senha: lab
useradd -m -s /bin/bash ops
echo 'ops:lab' | chpasswd
usermod -aG "$(getent group sudo >/dev/null && echo sudo || echo wheel)" ops

# PAM em container: pam_loginuid falha e derruba o login via SSH
sed -i 's/^session\s\+required\s\+pam_loginuid.so/session optional pam_loginuid.so/' /etc/pam.d/sshd || true
ssh-keygen -A

cat > /etc/motd <<EOF

  *** LAB: ${NAME} ***
  Zabbix proxy instalado via pacote (SQLite3). Comandos uteis:
    zabbix_proxy -V | head -1
    sudo systemctl status zabbix-proxy
    sudo tail -f /var/log/zabbix/zabbix_proxy.log
    cat /etc/zabbix/zabbix_proxy.conf | grep -v '^#' | grep -v '^$'

EOF
