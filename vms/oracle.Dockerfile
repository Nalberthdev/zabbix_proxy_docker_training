# "VM" Oracle Linux 9 com Zabbix proxy instalado via dnf (repo oficial Zabbix)
FROM oraclelinux:9

ARG ZBX_VERSION=6.0.46
ARG PROXY_NAME=proxy-oracle
ARG PROXY_MODE=1
ENV TZ=America/Sao_Paulo

RUN dnf -y install openssh-server openssh-clients sudo passwd procps-ng iproute \
      iputils bind-utils nmap-ncat vim-minimal nano less sqlite wget findutils \
      hostname tzdata \
 && dnf clean all

# Instalacao do Zabbix proxy 6.0 como na documentacao oficial
RUN rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/9/x86_64/zabbix-release-latest-6.0.el9.noarch.rpm \
 && dnf -y install zabbix-proxy-sqlite3-${ZBX_VERSION} \
 && dnf clean all

COPY common/systemctl /usr/local/bin/systemctl
COPY common/entrypoint.sh /usr/local/sbin/entrypoint.sh
COPY common/configure-proxy.sh /tmp/configure-proxy.sh
RUN chmod +x /usr/local/bin/systemctl /usr/local/sbin/entrypoint.sh \
 && bash /tmp/configure-proxy.sh "${PROXY_NAME}" "${PROXY_MODE}" && rm /tmp/configure-proxy.sh

EXPOSE 22 10051
ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
