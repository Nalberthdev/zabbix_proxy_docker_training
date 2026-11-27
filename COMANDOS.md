# Comandos: upgrade de proxy

```bash
# ACESSO
ssh -p 2222 ops@localhost ; ssh ops@proxy-ubuntu ; sudo su -     # senha: lab

# ANTES
zabbix_proxy -V | head -1 ; systemctl status zabbix-proxy
BKP=/root/bkp-$(date +%F-%H%M); mkdir -p $BKP; cp -a /etc/zabbix $BKP/

# TROCAR REPOSITORIO (so em upgrade de MAJOR; pular no patch)
# Ubuntu 7.0:
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb && dpkg -i zabbix-release_latest_7.0+ubuntu22.04_all.deb
# Ubuntu 8.0:
wget https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu22.04_all.deb && dpkg -i zabbix-release_latest_8.0+ubuntu22.04_all.deb
# Oracle 7.0:
rpm -Uvh https://repo.zabbix.com/zabbix/7.0/rhel/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
# Oracle 8.0:
rpm -Uvh https://repo.zabbix.com/zabbix/8.0/release/oracle/9/noarch/zabbix-release-latest-8.0.el9.noarch.rpm

# UPGRADE - Ubuntu
apt update ; apt-cache policy zabbix-proxy-sqlite3
systemctl stop zabbix-proxy
apt install --only-upgrade zabbix-proxy-sqlite3       # pergunta do .conf -> N

# UPGRADE - Oracle
dnf clean all ; dnf list --showduplicates zabbix-proxy-sqlite3
systemctl stop zabbix-proxy
dnf upgrade zabbix-proxy-sqlite3

# DEPOIS
zabbix_proxy -V | head -1
systemctl start zabbix-proxy ; systemctl status zabbix-proxy
grep -E '^(Server|Hostname|ProxyMode|DBName)=' /etc/zabbix/zabbix_proxy.conf
tail -30 /var/log/zabbix/zabbix_proxy.log
grep "Starting Zabbix Proxy" /var/log/zabbix/zabbix_proxy.log | tail -1   # versao do processo
ls -l /proc/$(cat /run/zabbix/zabbix_proxy.pid)/exe     # "(deleted)" = falta restart
zabbix_proxy -R config_cache_reload                    # so proxy ATIVO

# SERVER (no Mac, antes do major dos proxies)
docker compose exec -T postgres pg_dump -U zabbix zabbix | gzip > backups/zabbix-$(date +%F-%H%M).sql.gz
# editar .env: ZBX_SERVER_TAG e ZBX_WEB_TAG -> alpine-7.0-latest
docker compose pull zabbix-server zabbix-web ; docker compose up -d zabbix-server zabbix-web
docker compose logs -f zabbix-server

# RESET das VMs (volta tudo para 6.0.46)
docker compose up -d --force-recreate proxy-ubuntu proxy-oracle
```
