#!/bin/bash
# "Boot" da VM simulada: sobe o zabbix-proxy (se estiver enabled) e o sshd.
mkdir -p /run/sshd
rm -f /run/zabbix/*.pid 2>/dev/null
if [ -f /var/lib/lab-systemctl/zabbix-proxy.enabled ]; then
    /usr/local/bin/systemctl start zabbix-proxy || echo "zabbix-proxy falhou ao subir no boot"
fi
exec /usr/sbin/sshd -D -e
