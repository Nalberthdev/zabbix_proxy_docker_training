# "Servidor Jenkins" usado como bastion: voce entra aqui e daqui da SSH nos proxies
FROM ubuntu:22.04
ENV TZ=America/Sao_Paulo

RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server openssh-client sudo vim nano less iputils-ping dnsutils \
      netcat-openbsd tzdata \
 && rm -rf /var/lib/apt/lists/*

COPY common/entrypoint.sh /usr/local/sbin/entrypoint.sh
RUN chmod +x /usr/local/sbin/entrypoint.sh \
 && useradd -m -s /bin/bash ops && echo 'ops:lab' | chpasswd && usermod -aG sudo ops \
 && sed -i 's/^session\s\+required\s\+pam_loginuid.so/session optional pam_loginuid.so/' /etc/pam.d/sshd \
 && ssh-keygen -A \
 && printf '\n  *** LAB: jenkins (bastion) ***\n  Daqui voce acessa os proxies:\n    ssh ops@proxy-ubuntu     (Ubuntu 22.04, proxy ATIVO)\n    ssh ops@proxy-oracle     (Oracle Linux 9, proxy PASSIVO)\n  Senha de tudo: lab\n\n' > /etc/motd

EXPOSE 22
ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
