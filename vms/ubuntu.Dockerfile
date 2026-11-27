# "VM" Ubuntu 22.04 com Zabbix proxy instalado via apt (repo oficial Zabbix)
FROM ubuntu:22.04

ARG ZBX_VERSION=6.0.46
ARG PROXY_NAME=proxy-ubuntu
ARG PROXY_MODE=0
ENV TZ=America/Sao_Paulo

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server sudo ca-certificates wget curl vim nano less procps \
      iproute2 iputils-ping dnsutils netcat-openbsd sqlite3 tzdata \
 && rm -rf /var/lib/apt/lists/*

# Instalacao do Zabbix proxy 6.0 como na documentacao oficial
RUN wget -q https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_6.0+ubuntu22.04_all.deb -O /tmp/zabbix-release.deb \
 && dpkg -i /tmp/zabbix-release.deb && rm /tmp/zabbix-release.deb \
 && DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-proxy-sqlite3=1:${ZBX_VERSION}-1+ubuntu22.04 \
 && rm -rf /var/lib/apt/lists/*

COPY common/systemctl /usr/local/bin/systemctl
COPY common/entrypoint.sh /usr/local/sbin/entrypoint.sh
COPY common/configure-proxy.sh /tmp/configure-proxy.sh
RUN chmod +x /usr/local/bin/systemctl /usr/local/sbin/entrypoint.sh \
 && bash /tmp/configure-proxy.sh "${PROXY_NAME}" "${PROXY_MODE}" && rm /tmp/configure-proxy.sh

EXPOSE 22 10051
ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
