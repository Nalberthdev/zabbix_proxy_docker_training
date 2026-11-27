# Guia: upgrade de Zabbix proxy via SSH (para fazer sozinho)

Comandos resumidos: [COMANDOS.md](COMANDOS.md). Este guia explica cada passo e o que esperar.

## 0. O ambiente

```
Seu Mac  ->  jenkins (bastion)  ->  ssh  ->  proxy-ubuntu (Ubuntu 22.04, ATIVO)  -> agent-u
            localhost:2222                   proxy-oracle (Oracle 9,     PASSIVO) -> agent-o
```

- Os proxies sao instalados por pacote (apt/dnf) do repositorio oficial do Zabbix, com SQLite3.
- Comecam em **6.0.46**. O server comeca em **6.0.latest**.
- Usuario `ops`, senha `lab` em tudo. `sudo su -` para virar root.
- `systemctl` e simulado (container nao tem systemd), mas os comandos sao os mesmos.
- **No trabalho nao existe "tag"**: quem define a versao e o **repositorio** instalado (pacote `zabbix-release`).
  - Patch (6.0.46 -> 6.0.49): so `apt install` / `dnf upgrade`.
  - Major (6.0 -> 7.0): troca o repositorio e depois `apt install` / `dnf upgrade`.

Subir/ver o lab (no Mac, na pasta do projeto):

```bash
docker compose up -d
docker compose ps
```

Frontend: http://localhost:8080 (Admin / zabbix).

---

## 1. Regras que nao podem ser esquecidas

1. **Server primeiro, proxies depois.** Proxy nunca pode ser mais novo que o server.
2. Server suporta proxy da **mesma major** (Current) e da **LTS anterior** (Outdated, so coleta).
3. Server 8.0 **nao aceita** proxy 6.0. Por isso: 6.0 -> 7.0 -> 8.0 nos proxies.
4. Proxy com SQLite: na troca de major o arquivo do banco e **apagado e recriado**. Dados que estavam no buffer do proxy e nao foram enviados se perdem. E normal.
5. **Sempre parar o proxy antes** do upgrade.
6. Atualizar **so o pacote do Zabbix**. Nao rodar `apt upgrade` / `dnf upgrade` geral na janela.
7. **Olhar o prompt** antes de cada comando: `root@proxy-ubuntu` (e nao o Mac, nem o jenkins).

---

## 2. Exercicio 1: patch no proxy-ubuntu (6.0.46 -> 6.0.49)

### 2.1 Entrar

```bash
ssh -p 2222 ops@localhost
ssh ops@proxy-ubuntu
sudo su -
```

Primeira conexao pergunta `yes/no` (fingerprint): responder `yes`. A senha nao aparece ao digitar.

### 2.2 Estado antes

```bash
zabbix_proxy -V | head -1
systemctl status zabbix-proxy
grep -vE '^\s*(#|$)' /etc/zabbix/zabbix_proxy.conf
tail -20 /var/log/zabbix/zabbix_proxy.log
```

Esperado: versao 6.0.46, `active (running)`, log sem erro novo.
Se o log tiver erro **antes** do upgrade, resolva antes (ver secao 8). Comece sempre de um ambiente saudavel.

### 2.3 Backup

```bash
BKP=/root/bkp-$(date +%F-%H%M)
mkdir -p $BKP
cp -a /etc/zabbix $BKP/
dpkg -l | grep zabbix > $BKP/pacotes-antes.txt
ls -la $BKP
```

O SQLite nao precisa de backup: e buffer temporario, o proxy baixa a config do server de novo.

### 2.4 Ver o que vai ser instalado

```bash
apt update
apt-cache policy zabbix-proxy-sqlite3
```

- `Installed`: versao atual. `Candidate`: o que vai ser instalado.
- O Candidate fica na 6.0 porque o repositorio configurado e o da 6.0.
- Se aparecer pacote vindo de `archive.ubuntu.com` (ex. `5.0.17+dfsg`), e o Zabbix do proprio Ubuntu. Nao usar.

### 2.5 Upgrade

```bash
systemctl stop zabbix-proxy
systemctl status zabbix-proxy | head -3          # inactive (dead)
apt install --only-upgrade zabbix-proxy-sqlite3
```

Antes de confirmar `Y`, ler: deve ser `1 upgraded, 0 newly installed, 0 to remove`.
Se tiver algo em `to remove`: responder `n` e investigar.

### 2.6 Subir e validar

```bash
zabbix_proxy -V | head -1                         # 6.0.49
systemctl start zabbix-proxy
systemctl status zabbix-proxy
grep -E '^(Server|Hostname|ProxyMode|DBName)=' /etc/zabbix/zabbix_proxy.conf
tail -30 /var/log/zabbix/zabbix_proxy.log
dpkg -l | grep zabbix > $BKP/pacotes-depois.txt
```

Esperado no log: `received configuration data from server`.

Confirmar que o PROCESSO (nao so o pacote) e o novo:

```bash
grep "Starting Zabbix Proxy" /var/log/zabbix/zabbix_proxy.log | tail -1   # versao do processo rodando
ls -l /proc/$(cat /run/zabbix/zabbix_proxy.pid)/exe                          # "(deleted)" = falta restart
```

Frontend:
- *Administration -> Proxies*: *Last seen* de poucos segundos. (Coluna *Version* so existe a partir da 6.4; na 6.0 use o log acima.)
- *Configuration -> Hosts*: `agent-u` com ZBX verde.
- *Monitoring -> Latest data*: valores recentes do `agent-u`.

---

## 3. Exercicio 2: patch no proxy-oracle (6.0.46 -> 6.0.49)

Mesma logica, com `dnf`. Entrar: do jenkins, `ssh ops@proxy-oracle`, `sudo su -`.

```bash
zabbix_proxy -V | head -1
systemctl status zabbix-proxy
BKP=/root/bkp-$(date +%F-%H%M); mkdir -p $BKP; cp -a /etc/zabbix $BKP/
rpm -qa | grep zabbix > $BKP/pacotes-antes.txt

dnf clean all
dnf list --showduplicates zabbix-proxy-sqlite3   # @... = instalado; maior = disponivel

systemctl stop zabbix-proxy
dnf upgrade zabbix-proxy-sqlite3                 # ler a lista antes de confirmar "y"
zabbix_proxy -V | head -1
systemctl start zabbix-proxy
systemctl status zabbix-proxy
```

Diferenca do **proxy passivo**: quem manda a configuracao e o server. No lab o server envia a cada 60 s (`ZBX_PROXYCONFIGFREQUENCY: 60` no compose). Em producao o padrao e 3600 s (1 hora).
Espere 1 a 2 minutos e procure no log `received configuration data from server`.

Diferenca do **dnf**: se o pacote trouxer `.conf` novo, ele vira `/etc/zabbix/zabbix_proxy.conf.rpmnew` e o seu e mantido (nao pergunta nada).

---

## 4. Exercicio 3: atualizar o server para 7.0

Feito **no Mac**, na pasta do projeto. No trabalho, normalmente e outro time/procedimento, mas precisa acontecer antes dos proxies.

```bash
mkdir -p backups
docker compose exec -T postgres pg_dump -U zabbix zabbix | gzip > backups/zabbix-6.0-$(date +%F-%H%M).sql.gz
ls -lh backups/
```

Editar o `.env`:

```dotenv
ZBX_SERVER_TAG=alpine-7.0-latest
ZBX_WEB_TAG=alpine-7.0-latest
```

```bash
docker compose pull zabbix-server zabbix-web
docker compose up -d zabbix-server zabbix-web
docker compose logs -f zabbix-server
```

Esperado no log: varias linhas de `database upgrade` e por fim `database upgrade fully completed`. **Nao interromper.** Ctrl+C so sai do log, nao para o server.

Depois, em *Administration -> Proxies*, os proxies 6.0 aparecem como **Outdated**: ainda coletam, mas nao recebem configuracao nova. Esse e o estado "server ja atualizado, proxies pendentes" que voce vai ver em producao.

Os proxies antigos em container (`proxy-ativo`, `proxy-passivo`) tambem ficam Outdated. Para eles, o upgrade e por tag: `ZBX_PROXY_ACTIVE_TAG` / `ZBX_PROXY_PASSIVE_TAG` no `.env` e `docker compose up -d proxy-ativo proxy-passivo`.

---

## 5. Exercicio 4: major no proxy-ubuntu (6.0 -> 7.0)

```bash
# estado antes + backup (igual 2.2 e 2.3)

systemctl stop zabbix-proxy

wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb
dpkg -i zabbix-release_latest_7.0+ubuntu22.04_all.deb
apt update
apt-cache policy zabbix-proxy-sqlite3            # Candidate agora e 7.0.x

apt install --only-upgrade zabbix-proxy-sqlite3
```

**Pergunta do arquivo de configuracao.** O dpkg vai perguntar algo como:

```
Configuration file '/etc/zabbix/zabbix_proxy.conf'
 ==> Modified (by you or by a script) since installation.
 ==> Package distributor has shipped an updated version.
   What would you like to do about it ?
    Y or I  : install the package maintainer's version
    N or O  : keep your currently-installed version
      D     : show the differences between the versions
```

- `D` mostra a diferenca (vale olhar para aprender o que mudou).
- Responder **`N`**: mantem a sua config (Server, Hostname, ProxyMode, DBName).
- Se responder `Y` por engano: o proxy volta a `Hostname=Zabbix proxy`, `Server=127.0.0.1`. Restaure com `cp $BKP/zabbix/zabbix_proxy.conf /etc/zabbix/`.

```bash
zabbix_proxy -V | head -1                         # 7.0.x
systemctl start zabbix-proxy
tail -50 /var/log/zabbix/zabbix_proxy.log
```

Esperado no log: mensagem de que a versao do banco SQLite nao bate e que o arquivo foi **removido e recriado**. Depois `received configuration data from server`.

Frontend (7.0): menu mudou para *Administration -> Proxies* (novo layout) e *Data collection -> Hosts*. Proxy deve ficar **Current**.

---

## 6. Exercicio 5: major no proxy-oracle (6.0 -> 7.0)

```bash
systemctl stop zabbix-proxy
rpm -Uvh https://repo.zabbix.com/zabbix/7.0/rhel/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm
dnf clean all
dnf list --showduplicates zabbix-proxy-sqlite3
dnf upgrade zabbix-proxy-sqlite3
zabbix_proxy -V | head -1
ls /etc/zabbix/                                   # pode ter zabbix_proxy.conf.rpmnew
systemctl start zabbix-proxy
tail -50 /var/log/zabbix/zabbix_proxy.log
```

Para comparar o .conf novo com o seu: `diff /etc/zabbix/zabbix_proxy.conf /etc/zabbix/zabbix_proxy.conf.rpmnew`.

Proxy passivo depois de major: o SQLite foi recriado **vazio**, entao ele fica sem configuracao ate o server enviar.
No frontend 7.0 da para forcar: *Administration -> Proxies*, marcar o proxy, botao **Refresh configuration**.

---

## 7. Exercicio 6: tudo para 8.0

Mesma sequencia das secoes 4, 5 e 6, trocando 7.0 por 8.0:

1. Backup do Postgres, `.env` com `alpine-8.0-latest` no server e web, `pull` e `up -d`.
2. Proxies (repositorio da 8.0 tem outro caminho):

```bash
# Ubuntu
wget https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu22.04_all.deb
dpkg -i zabbix-release_latest_8.0+ubuntu22.04_all.deb
# Oracle
rpm -Uvh https://repo.zabbix.com/zabbix/8.0/release/oracle/9/noarch/zabbix-release-latest-8.0.el9.noarch.rpm
```

Antes, ler as *upgrade notes* da 8.0 (versao minima de banco/PHP). Se o server 8.0 recusar o PostgreSQL por versao, ver o log; em lab da para liberar com `ZBX_ALLOWUNSUPPORTEDDBVERSIONS: "true"` no environment do server.

Para treinar o erro classico: suba o server para 8.0 com um proxy ainda em 6.0 e veja os dados dele serem ignorados.

---

## 8. Problemas que ja apareceram (e a solucao)

| Sintoma | Causa | Solucao |
|---|---|---|
| Log do server: `proxy "X" not found` | Proxy nao cadastrado ou nome diferente do `Hostname` do .conf | Cadastrar em *Proxies* com o nome exato (diferencia maiusculas) |
| Log do proxy: `host [agent-x] not found` | Proxy ainda sem config nova | Ativo: `zabbix_proxy -R config_cache_reload`. Passivo: esperar o envio do server (ou *Refresh configuration* no 7.0+) |
| Log do agent: `connection from "IP" rejected, allowed hosts: ...` | Quem conecta nao e o proxy do agent (ex.: host sem *Monitored by proxy*) | Conferir *Monitored by proxy* no host. Descobrir o IP: `docker network inspect zabbix-lab_zbx-net` |
| Agent recusando o proxy logo apos subir o lab | Agent subiu antes do proxy e nao resolveu o nome | `docker compose restart agent-x` |
| Frontend: `Interface with DNS "x" cannot have empty IP address` | *Connect to* marcado em IP | Clicar no botao **DNS** em *Connect to* |
| Comando "nao encontrado" / nada acontece | Rodou no Mac ou no jenkins, nao no proxy | Olhar o prompt; voltar com ssh |
| `Failed to start ... Access denied` | Sem root | `sudo` ou `sudo su -` |
| Proxy nao sobe apos upgrade | Ver o log | `tail -50 /var/log/zabbix/zabbix_proxy.log` e `grep -E '^(Server|Hostname|ProxyMode|DBName)=' /etc/zabbix/zabbix_proxy.conf` |
| Config sumiu apos upgrade (Hostname=Zabbix proxy) | Respondeu `Y` na pergunta do .conf | Restaurar do `$BKP` e `systemctl restart zabbix-proxy` |

---

## 9. Rollback

**Proxy** (simples, o proxy nao guarda nada importante):

```bash
systemctl stop zabbix-proxy
cp -a $BKP/zabbix/* /etc/zabbix/
rm -f /var/lib/zabbix/zabbix_proxy.db             # necessario em rollback de major
# Ubuntu: dpkg -i no zabbix-release da versao antiga, apt update, e:
apt install --allow-downgrades zabbix-proxy-sqlite3=<versao>     # versoes: apt-cache policy
# Oracle: rpm -Uvh no zabbix-release antigo, e:
dnf downgrade zabbix-proxy-sqlite3-<versao>
systemctl start zabbix-proxy
```

**Server**: precisa restaurar o backup do Postgres (ver README, exercicio 3).

**Atalho do lab**: recriar as VMs do zero em 6.0.46:

```bash
docker compose up -d --force-recreate proxy-ubuntu proxy-oracle
```

---

## 10. Checklist para cada proxy no trabalho

- [ ] Janela combinada / Maintenance cadastrada para os hosts do proxy
- [ ] Server ja na versao alvo (em major)
- [ ] ssh no proxy certo (conferir prompt e `hostname`)
- [ ] Versao, status e log antes (anotar)
- [ ] Backup do `/etc/zabbix` e lista de pacotes
- [ ] Repositorio certo (`apt-cache policy` / `dnf list`)
- [ ] stop -> upgrade (so o pacote do Zabbix) -> conferir versao -> start
- [ ] .conf preservado (Server, Hostname, ProxyMode, DBName)
- [ ] Log sem erro, `received configuration data`
- [ ] Frontend: versao, Last seen, hosts verdes, Latest data
- [ ] Registrar pacotes depois / fechar a mudanca
