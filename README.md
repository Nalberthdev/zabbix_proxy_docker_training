# Lab Zabbix: atualizando Proxies

Lab para treinar a atualização de Zabbix Server e Proxies, **partindo do Zabbix 6.0 LTS, passando pelo 7.0 LTS e chegando no 8.0 LTS**.

Caminho do lab: `6.0 → 7.0 → 8.0`

O lab tem duas trilhas:

| Trilha | Proxies | Como atualiza | Para que serve |
|---|---|---|---|
| **A. Containers** | `proxy-ativo`, `proxy-passivo` (imagens oficiais) | troca a tag no `.env` e `docker compose up -d` | entender compatibilidade e comportamento do server/proxy rapidamente |
| **B. "VMs" via SSH** | `proxy-ubuntu`, `proxy-oracle` (instalados por pacote) | `ssh` + `apt` / `dnf`, como no dia a dia | treinar o procedimento real de trabalho |

Guia passo a passo da trilha B: **[GUIA-UPGRADE-PROXY.md](GUIA-UPGRADE-PROXY.md)**. Colinha de comandos: **[COMANDOS.md](COMANDOS.md)**.

## Topologia

```
                         +-------------+
                         | zabbix-web  | :8080
                         +------+------+
                                |
  +----------+          +-------+--------+
  | postgres |----------| zabbix-server  | :10051
  +----------+          +---+---+---+---++
                            |   |   |   |
     TRILHA A (containers)  |   |   |   |  TRILHA B ("VMs" via pacote)
         +------------------+   |   |   +------------------+
         |              +-------+   +-------+              |
   proxy-ativo    proxy-passivo       proxy-ubuntu    proxy-oracle
   (ativo)        (passivo)           Ubuntu 22.04    Oracle Linux 9
         |              |             (ativo, apt)    (passivo, dnf)
      agent-a        agent-p              |              |
                                       agent-u        agent-o
                                          ^              ^
                                          +---- ssh -----+
                                                 |
                                          jenkins (bastion) :2222
                                                 ^
                                              seu Mac
```

- 1 server + web + PostgreSQL 16 (suportado em 6.0, 7.0 e 8.0, sem precisar trocar a major do banco).
- 4 proxies, todos com **SQLite3**: 2 ativos e 2 passivos.
- 1 agent2 atrás de cada proxy.
- Tudo começa em **6.0 LTS**. Os proxies da trilha B começam em **6.0.46**, para treinar também o patch dentro da major.

## 1. Regras de compatibilidade (leia antes de atualizar)

Segundo a documentação oficial do Zabbix:

- O server suporta totalmente proxies da **mesma versão major**.
- Proxies da **LTS anterior** funcionam, mas com funcionalidade limitada (coleta de dados, comandos remotos, checagem imediata). Esses proxies são chamados de *outdated*.
- Proxies **mais novos que o server** ou **mais antigos que a LTS anterior** não são suportados. O server ignora os dados deles.
- Ordem recomendada: **atualizar o server primeiro e depois os proxies, um por um**. Os proxies continuam coletando enquanto o server está parado.
- Proxy com **SQLite3**: se na subida o arquivo de banco for de versão mais antiga, o Zabbix **apaga e recria** o arquivo. O histórico que estava no proxy e ainda não foi enviado se perde.

Referência: https://www.zabbix.com/documentation/current/en/manual/installation/upgrade

### O que isso significa para o caminho 6.0 → 7.0 → 8.0

| Server | Proxy 6.0 | Proxy 7.0 | Proxy 8.0 |
|---|---|---|---|
| 6.0 | Current | Não suportado (mais novo que o server) | Não suportado |
| 7.0 | Outdated (LTS anterior) | Current | Não suportado |
| 8.0 | **Não suportado** (mais antigo que a LTS anterior) | Outdated (LTS anterior) | Current |

Consequências práticas:

- Ao subir o server em 7.0, os proxies 6.0 ainda funcionam (*Outdated*). Atualize-os para 7.0 em seguida.
- **Não pule os proxies**: se o server for para 8.0 com proxies ainda em 6.0, o server ignora os dados deles.
- O server pode, em teoria, ir direto de 6.0 para 8.0, mas os proxies precisam acompanhar. O exercício 4b treina essa variação.
- A coluna *Version* / *Compatibility* em *Administration → Proxies* só existe no frontend a partir da **6.4**. Na 6.0, a versão do proxy se confere no log dele (`grep "Starting Zabbix Proxy"`).

## 2. Estrutura do repo

```
.
├── .env.example              # copiar para .env (o .env não é versionado)
├── docker-compose.yml
├── README.md                 # este arquivo
├── GUIA-UPGRADE-PROXY.md     # passo a passo da trilha B (SSH + apt/dnf)
├── COMANDOS.md               # colinha de comandos
└── vms/                      # imagens das "VMs" da trilha B
    ├── ubuntu.Dockerfile     # Ubuntu 22.04 + zabbix-proxy-sqlite3 via apt
    ├── oracle.Dockerfile     # Oracle Linux 9 + zabbix-proxy-sqlite3 via dnf
    ├── jenkins.Dockerfile    # bastion (simula o servidor Jenkins)
    └── common/
        ├── systemctl         # systemctl simulado (container não tem systemd)
        ├── entrypoint.sh     # "boot" da VM: sobe proxy + sshd
        └── configure-proxy.sh# ajusta o zabbix_proxy.conf e cria o usuário ops
```

## 3. Subindo o lab

```bash
cp .env.example .env            # e troque a senha do Postgres
docker compose config -q && echo "compose OK"
docker compose build            # imagens das VMs (trilha B); leva alguns minutos
docker compose up -d
docker compose ps
docker compose logs -f zabbix-server     # aguarde "server #0 started [main process]"
```

| Acesso | Endereço | Usuário / senha |
|---|---|---|
| Frontend | http://localhost:8080 | `Admin` / `zabbix` (troque depois do primeiro login) |
| Jenkins (bastion) | `ssh -p 2222 ops@localhost` | `ops` / `lab` |
| Proxies da trilha B (a partir do jenkins) | `ssh ops@proxy-ubuntu`, `ssh ops@proxy-oracle` | `ops` / `lab`, depois `sudo su -` |
| PostgreSQL | `docker compose exec postgres psql -U zabbix -d zabbix` | (porta não exposta ao Mac) |

### Ajustes do compose que importam

- `ZBX_PROXYCONFIGFREQUENCY: 60` no server: envia a configuração aos proxies **passivos** a cada 60 s. O padrão é 3600 s (1 hora); sem isso, um proxy passivo recém-cadastrado ou recém-atualizado fica até 1 hora sem coletar.
- `depends_on` nos agents: o agent2 resolve o nome do proxy (`ZBX_SERVER_HOST`) quando sobe. Se subir antes do proxy, recusa as conexões dele.

### Cadastrando os proxies no frontend

Em *Administration → Proxies → Create proxy*:

| Proxy name | Proxy mode | Interface (só passivo) |
|---|---|---|
| `proxy-ativo` | Active | n/a |
| `proxy-passivo` | Passive | DNS `proxy-passivo`, porta `10051`, Connect to **DNS** |
| `proxy-ubuntu` | Active | n/a |
| `proxy-oracle` | Passive | DNS `proxy-oracle`, porta `10051`, Connect to **DNS** |

O *Proxy name* tem que ser **igual** ao `Hostname` do proxy (diferencia maiúsculas). Use **DNS e não IP**: no Docker, o IP do container pode mudar quando ele é recriado.

### Cadastrando os hosts

Em *Configuration → Hosts → Create host* (a partir do 7.0: *Data collection → Hosts*). Para todos: template `Linux by Zabbix agent`, grupo `Linux servers`, interface Agent porta `10050` com **Connect to: DNS**.

| Host name | Interface (DNS) | Monitored by proxy |
|---|---|---|
| `agent-a` | `agent-a` | `proxy-ativo` |
| `agent-p` | `agent-p` | `proxy-passivo` |
| `agent-u` | `agent-u` | `proxy-ubuntu` |
| `agent-o` | `agent-o` | `proxy-oracle` |

Não esqueça o **Monitored by proxy**: sem ele, o server tenta consultar o agent direto e o agent recusa (ele só aceita o proxy dele).

Também dá para cadastrar tudo pela API com um token (*Administration → General → API tokens*), via `proxy.create` e `host.create` em `http://localhost:8080/api_jsonrpc.php`.

Depois de 1 a 2 minutos, os hosts devem ficar com o ícone ZBX verde e a coluna *Last seen* dos proxies deve atualizar.

O host padrão "Zabbix server" fica vermelho (não há agent no container do server). Pode desativá-lo.

## 4. Exercícios

Antes de cada exercício, anote o estado (versão e *Last seen* dos proxies) e **faça backup do banco** (no Mac):

```bash
mkdir -p backups
docker compose exec -T postgres pg_dump -U zabbix zabbix | gzip > backups/zabbix-$(date +%F-%H%M).sql.gz
```

> macOS: `sed -i` precisa de `''` logo depois (`sed -i '' 's/.../.../' .env`). No Linux é só `sed -i`.

### Trilha B: upgrade via SSH (procedimento de trabalho)

Siga o **[GUIA-UPGRADE-PROXY.md](GUIA-UPGRADE-PROXY.md)**:

1. Patch no `proxy-ubuntu` (6.0.46 → 6.0.49, `apt`)
2. Patch no `proxy-oracle` (6.0.46 → 6.0.49, `dnf`)
3. Server para 7.0 (por tag, no Mac)
4. Major no `proxy-ubuntu` (6.0 → 7.0: troca do repositório, pergunta do `.conf`, SQLite recriado)
5. Major no `proxy-oracle` (6.0 → 7.0: `.rpmnew`, proxy passivo sem configuração até o server enviar)
6. Tudo para 8.0

As "VMs" se comportam como servidores: o upgrade feito com `apt`/`dnf` fica dentro do container. Para voltar tudo a 6.0.46 (reinstalar a VM):

```bash
docker compose up -d --force-recreate proxy-ubuntu proxy-oracle
```

### Trilha A, exercício 1: atualizar só o proxy dentro da mesma major (6.0.x)

1. Fixe uma tag antiga no `.env`, por exemplo `ZBX_PROXY_ACTIVE_TAG=alpine-6.0.20`. Confira se a tag existe e tem a sua arquitetura:
   ```bash
   docker manifest inspect zabbix/zabbix-proxy-sqlite3:alpine-6.0.20 | grep '"architecture"' | sort -u
   ```
2. `docker compose up -d proxy-ativo` e confirme a versão:
   ```bash
   docker compose exec proxy-ativo zabbix_proxy -V | head -1
   ```
3. Troque a tag para `alpine-6.0-latest` e rode:
   ```bash
   docker compose pull proxy-ativo
   docker compose up -d proxy-ativo
   docker compose logs --tail=50 proxy-ativo
   docker compose exec proxy-ativo zabbix_proxy -V | head -1
   ```
4. No frontend, confira *Administration → Proxies*: *Last seen* recente.

O que observar: o `up -d` recria só o container cuja imagem mudou. O volume com o SQLite é reaproveitado.

### Trilha A, exercício 2: upgrade major em etapas, 6.0 → 7.0 → 8.0

**Etapa A: 6.0 → 7.0**

1. **Backup** do PostgreSQL (comando acima).
2. Atualize **server e web** no `.env`:
   ```dotenv
   ZBX_SERVER_TAG=alpine-7.0-latest
   ZBX_WEB_TAG=alpine-7.0-latest
   ```
   ```bash
   docker compose pull zabbix-server zabbix-web
   docker compose up -d zabbix-server zabbix-web
   docker compose logs -f zabbix-server   # acompanhe a migração do schema; não interrompa
   ```
3. Com os proxies ainda na 6.0, abra *Administration → Proxies*. Eles devem aparecer como **Outdated**. O server recebe dados deles, mas não envia configuração nova.
4. Atualize o **proxy-ativo**:
   ```bash
   sed -i '' 's/^ZBX_PROXY_ACTIVE_TAG=.*/ZBX_PROXY_ACTIVE_TAG=alpine-7.0-latest/' .env
   docker compose pull proxy-ativo
   docker compose up -d proxy-ativo
   docker compose logs -f proxy-ativo
   ```
   Procure no log a mensagem de que o SQLite foi recriado. É esperado na troca de versão.
5. Repita para o **proxy-passivo** (`ZBX_PROXY_PASSIVE_TAG`).
6. Atualize os **agents** (opcional):
   ```bash
   sed -i '' 's/^ZBX_AGENT_TAG=.*/ZBX_AGENT_TAG=alpine-7.0-latest/' .env
   docker compose up -d agent-a agent-p agent-u agent-o
   ```
7. Valide: proxies em *Current*, hosts com ZBX verde, *Latest data* chegando. Faça um novo backup.

**Etapa B: 7.0 → 8.0**

Repita o mesmo roteiro trocando `7.0` por `8.0`. Antes, leia as *upgrade notes* da 8.0 (versões mínimas de banco e PHP). Se o server recusar a versão do PostgreSQL, veja o log; em lab dá para liberar com `ZBX_ALLOWUNSUPPORTEDDBVERSIONS: "true"` no server. Troca de major do PostgreSQL exige dump/restore, não basta mudar a tag.

**Dica:** a partir do 7.0 existem *proxy groups*, o formulário de proxy mudou e há o botão **Refresh configuration** em *Administration → Proxies* (força o envio de config para o proxy).

### Exercício 3: rollback

Objetivo: entender que o downgrade de **server** exige restaurar o backup do banco.

1. Pare tudo: `docker compose down` (sem `-v`).
2. Volte as tags do `.env` para a versão anterior (a do backup).
3. Restaure o dump:
   ```bash
   docker compose up -d postgres
   gunzip -c backups/<arquivo>.sql.gz | docker compose exec -T postgres psql -U zabbix -d zabbix
   ```
   Se der conflito de objetos, recrie o banco antes (`DROP DATABASE`/`CREATE DATABASE`) ou apague o volume com `docker compose down -v` e restaure em banco limpo.
4. `docker compose up -d` e valide.

Para proxy o rollback é mais simples: volte a versão (tag ou pacote), apague o SQLite e suba de novo. O proxy recebe a configuração do server outra vez. Na trilha B, ver a seção de rollback do guia.

### Exercício 4: cenários não suportados

**4a. Proxy mais novo que o server**

1. Com tudo em 6.0, suba `proxy-ativo` em `alpine-7.0-latest`.
2. Observe no log do server o aviso de proxy não suportado e que os dados dele são ignorados.
3. Volte a tag do proxy para a mesma major do server.

**4b. Proxy 6.0 com server 8.0 (pulando a 7.0 nos proxies)**

1. Refaça o lab do zero (`docker compose down -v` e `up -d` em 6.0) e tire um backup.
2. Atualize server e web direto para `alpine-8.0-latest`. Mantenha os proxies em 6.0.
3. Observe os avisos nos logs e o status dos proxies. Os dados dos proxies 6.0 são ignorados.
4. Atualize os proxies direto para 8.0 e veja a recuperação.

### Exercício 5: derrubar o server e ver o proxy bufferizar

1. `docker compose stop zabbix-server`
2. Espere alguns minutos. Os proxies continuam coletando e guardando em SQLite.
3. `docker compose start zabbix-server`
4. Veja os dados do período chegando em *Latest data* e nos gráficos.

O tempo que o proxy guarda dados é controlado por `ProxyOfflineBuffer` (em horas): `ZBX_PROXYOFFLINEBUFFER` nos proxies em container, ou direto no `zabbix_proxy.conf` nas VMs.

## 5. Comandos úteis

```bash
# no Mac
docker compose ps
docker compose logs -f --tail=100 proxy-ativo
docker compose exec zabbix-server zabbix_server -V | head -1
docker compose exec zabbix-server zabbix_server -R config_cache_reload
docker network inspect zabbix-lab_zbx-net -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'
docker compose exec postgres psql -U zabbix -d zabbix -c "SELECT * FROM dbversion;"

# dentro de um proxy da trilha B (como root)
zabbix_proxy -V | head -1
systemctl status zabbix-proxy
tail -f /var/log/zabbix/zabbix_proxy.log
grep "Starting Zabbix Proxy" /var/log/zabbix/zabbix_proxy.log | tail -1
zabbix_proxy -R config_cache_reload        # só proxy ATIVO

# limpar tudo e recomeçar o lab
docker compose down -v
```

## 6. Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| Log do server: `proxy "X" not found` | Proxy não cadastrado ou `Hostname` diferente do *Proxy name* (diferencia maiúsculas) | Cadastrar com o nome exato |
| Log do proxy: `host [agent-x] not found` | Proxy ainda sem a configuração nova | Ativo: `zabbix_proxy -R config_cache_reload`. Passivo: esperar o envio do server (60 s no lab) ou *Refresh configuration* (6.4+) |
| Proxy passivo nunca recebe config | `ProxyConfigFrequency` padrão (3600 s); restart do server não força o envio na 6.0 | `ZBX_PROXYCONFIGFREQUENCY: 60` no server (já no compose) |
| Log do agent: `connection from "IP" rejected` com IP do server | Host sem *Monitored by proxy* | Ajustar o host no frontend |
| Agent recusa o próprio proxy logo após subir | Agent subiu antes do proxy | `docker compose restart agent-x` (o `depends_on` evita) |
| Frontend: `Interface with DNS "x" cannot have empty IP address` | *Connect to* marcado como IP | Clicar em **DNS** em *Connect to* |
| Server não sobe após trocar tag | Banco ainda migrando | `docker compose logs zabbix-server`. Não interrompa a migração |
| Dados do proxy ignorados pelo server | Proxy mais novo que o server, ou mais antigo que a LTS anterior | Ajustar versões (seção 1) |
| Pacote novo instalado, mas proxy na versão velha | Atualizou sem parar/reiniciar o serviço | `systemctl restart zabbix-proxy`; `ls -l /proc/<pid>/exe` mostra `(deleted)` |
| `docker: command not found` | Comando de Mac rodado dentro do proxy | Olhar o prompt |
| Tag não encontrada no `pull` | Nome errado ou sem a sua arquitetura | `docker manifest inspect` |

## 7. Próximos passos para evoluir o lab

- Automatizar o roteiro da trilha B num job Jenkins / script (checagem de versão antes e depois, um proxy por vez).
- Trocar SQLite por MySQL/PostgreSQL no proxy e comparar o comportamento no upgrade.
- Adicionar **proxy groups** (7.0+) com 2 proxies e testar failover.
- Criptografia PSK entre proxy e server.
- Uma VM Debian na trilha B.

## Referências

- Upgrade: https://www.zabbix.com/documentation/current/en/manual/installation/upgrade
- Compatibilidade de versões: https://www.zabbix.com/documentation/current/en/manual/appendix/compatibility
- Instalação por pacotes: https://www.zabbix.com/download
- Imagens Docker: https://hub.docker.com/u/zabbix
