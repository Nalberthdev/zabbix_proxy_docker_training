# Lab Zabbix: atualizando Proxies com Docker Compose

Lab para treinar o fluxo de atualização de Zabbix Server e Proxies usando Docker Compose, **partindo do Zabbix 6.0 LTS, passando pelo 7.0 LTS e chegando no 8.0 LTS**.

Caminho do lab: `6.0 → 7.0 → 8.0`

**Topologia**

```
                +-------------------+
                |   zabbix-web      | :8080
                +---------+---------+
                          |
 +----------+    +--------+--------+
 | postgres |----|  zabbix-server  | :10051
 +----------+    +----+-------+----+
                      |       |
        (ativo: proxy  |       | (passivo: server conecta no proxy)
         conecta aqui) |       |
              +--------+--+  +-+------------+
              | proxy-ativo|  | proxy-passivo|
              +-----+------+  +------+-------+
                    |                |
              agent-a (host)   agent-p (host)
```

- 1 server + web + PostgreSQL
- 2 proxies (SQLite3): um em modo **ativo** e outro em modo **passivo**
- 1 agent2 atrás de cada proxy
- Todos os componentes começam em **6.0 LTS**. As versões são controladas por variáveis no `.env`, então a atualização é só trocar a tag e rodar `up -d`.

## 1. Regras de compatibilidade (leia antes de atualizar)

Segundo a documentação oficial do Zabbix:

- O server suporta totalmente proxies da **mesma versão major**.
- Proxies da **LTS anterior** funcionam, mas com funcionalidade limitada (coleta de dados, comandos remotos, checagem imediata). Esses proxies são chamados de *outdated*.
- Proxies **mais novos que o server** ou **mais antigos que a LTS anterior** não são suportados. O server ignora os dados deles.
- Ordem recomendada: **atualizar o server primeiro e depois os proxies, um por um**. Os proxies continuam coletando enquanto o server está parado.
- Proxy com **SQLite3**: se na subida o arquivo de banco for de versão mais antiga, o Zabbix **apaga e recria** o arquivo. O histórico que estava no proxy e ainda não foi enviado se perde. Este lab usa SQLite justamente para você observar isso.

Referência: https://www.zabbix.com/documentation/current/en/manual/installation/upgrade

### O que isso significa para o caminho 6.0 → 7.0 → 8.0

| Server | Proxy 6.0 | Proxy 7.0 | Proxy 8.0 |
|---|---|---|---|
| 6.0 | Current | Não suportado (mais novo que o server) | Não suportado |
| 7.0 | Outdated (LTS anterior) | Current | Não suportado |
| 8.0 | **Não suportado** (mais antigo que a LTS anterior) | Outdated (LTS anterior) | Current |

Consequências práticas:

- Ao subir o server em 7.0, os proxies 6.0 ainda funcionam (*Outdated*). Atualize-os para 7.0 em seguida.
- **Não pule os proxies**: se o server for para 8.0 com proxies ainda em 6.0, o server ignora os dados deles. Por isso o lab passa pela 7.0 nos proxies.
- O server pode, em teoria, ir direto de 6.0 para 8.0 (a documentação lista upgrade direto de 6.0.x), mas os proxies precisam acompanhar. O exercício 4b treina essa variação.

## 2. Estrutura do repo

```
.
├── .env
├── docker-compose.yml
├── .gitignore
└── README.md
```

## 3. Subindo o lab

```bash
docker compose config -q && echo "compose OK"
docker compose up -d
docker compose ps
docker compose logs -f zabbix-server     # aguarde "server #0 started [main process]"
```

Frontend: http://localhost:8080 (usuário `Admin`, senha `zabbix`). **Troque a senha** depois do primeiro login, mesmo sendo lab.

### Cadastrando os proxies no frontend

Em *Administration → Proxies → Create proxy* (no 6.0 o formulário é este; no 7.0 e 8.0 ele muda de layout, mas os campos são equivalentes):

| Campo | proxy-ativo | proxy-passivo |
|---|---|---|
| Proxy name | `proxy-ativo` | `proxy-passivo` |
| Proxy mode | Active | Passive |
| Interface (passivo) | n/a | Address/DNS `proxy-passivo`, porta `10051` |

### Cadastrando os hosts

Em *Configuration → Hosts → Create host* (a partir do 7.0 o menu passa a ser *Data collection → Hosts*):

| Host name | Template | Interface agent (DNS, porta 10050) | Monitored by |
|---|---|---|---|
| `agent-a` | Linux by Zabbix agent | `agent-a` | Proxy → `proxy-ativo` |
| `agent-p` | Linux by Zabbix agent | `agent-p` | Proxy → `proxy-passivo` |

Depois de 1 a 2 minutos, os hosts devem ficar com o ícone ZBX verde, e em *Administration → Proxies* a coluna *Last seen* deve atualizar.

> Dica: no `agent-a` e `agent-p` marque também o campo "Connect to: DNS".

## 4. Exercícios de atualização

Antes de cada exercício, anote o estado (versão e *Last seen* dos proxies) e **faça backup do banco**:

```bash
mkdir -p backups
docker compose exec -T postgres pg_dump -U zabbix zabbix | gzip > backups/zabbix-$(date +%F-%H%M).sql.gz
```

### Exercício 1: atualizar só o proxy dentro da mesma major (6.0.x)

Objetivo: o fluxo mais simples de atualização de proxy.

1. Fixe uma tag antiga no `.env` para ter o que atualizar, por exemplo `ZBX_PROXY_ACTIVE_TAG=alpine-6.0.0` (confira se a tag existe no Docker Hub).
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
4. No frontend, confira *Administration → Proxies*: versão nova e *Last seen* recente.

O que observar: o `up -d` recria só o container cujo image mudou. O volume com o SQLite é reaproveitado.

### Exercício 2: upgrade major em etapas, 6.0 → 7.0 → 8.0

Objetivo: reproduzir o fluxo oficial (server primeiro, proxies depois), duas vezes.

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
   sed -i 's/^ZBX_PROXY_ACTIVE_TAG=.*/ZBX_PROXY_ACTIVE_TAG=alpine-7.0-latest/' .env
   docker compose pull proxy-ativo
   docker compose up -d proxy-ativo
   docker compose logs -f proxy-ativo
   ```
   Procure no log a mensagem de que o SQLite foi recriado. É esperado na troca de versão.
5. Repita para o **proxy-passivo** (`ZBX_PROXY_PASSIVE_TAG`).
6. Atualize os **agents** (opcional):
   ```bash
   sed -i 's/^ZBX_AGENT_TAG=.*/ZBX_AGENT_TAG=alpine-7.0-latest/' .env
   docker compose up -d agent-a agent-p
   ```
7. Valide: proxies em *Current*, hosts com ZBX verde, *Latest data* chegando. Faça um novo backup e um commit (`git commit -am "lab em 7.0"`).

**Etapa B: 7.0 → 8.0**

Repita exatamente o mesmo roteiro trocando `7.0` por `8.0`. Antes, leia as *upgrade notes* da 8.0, que trazem requisitos novos (versões mínimas de banco e PHP, por exemplo). Se o banco ficar abaixo do mínimo, suba a versão do PostgreSQL com cuidado: troca de major do PostgreSQL exige dump/restore, não basta mudar a tag.

Depois da etapa B, compare em *Administration → Proxies* o estado de cada proxy a cada passo. Isso é o que você vai ver em produção.

**Dica de ambiente:** a partir do 7.0 existem *proxy groups* e o formulário de proxy mudou. Aproveite para explorar a tela nova depois da etapa A.

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

Para proxy o rollback é mais simples: volte a tag e suba de novo. Como o SQLite é descartável, o proxy recebe a configuração do server outra vez.

### Exercício 4: cenários não suportados

Objetivo: ver na prática o que acontece quando a regra de compatibilidade é violada.

**4a. Proxy mais novo que o server**

1. Com tudo em 6.0, suba `proxy-ativo` em `alpine-7.0-latest`.
2. Observe no log do server o aviso de proxy não suportado e que os dados dele são ignorados.
3. Volte a tag do proxy para a mesma major do server.

**4b. Proxy 6.0 com server 8.0 (pulando a 7.0 nos proxies)**

1. Refaça o lab do zero (`docker compose down -v` e `up -d` em 6.0) e tire um backup.
2. Atualize server e web direto para `alpine-8.0-latest` (upgrade direto de 6.0 é listado na documentação). Mantenha os proxies em 6.0.
3. Observe os avisos nos logs e o status dos proxies. Os dados dos proxies 6.0 são ignorados.
4. Atualize os proxies direto para 8.0 e veja a recuperação.

### Exercício 5: derrubar o server e ver o proxy bufferizar

1. `docker compose stop zabbix-server`
2. Espere alguns minutos. Os proxies continuam coletando e guardando em SQLite.
3. `docker compose start zabbix-server`
4. Veja os dados do período chegando em *Latest data* e nos gráficos.

Dica: o tempo que o proxy guarda dados é controlado por `ProxyOfflineBuffer` (em horas). Ajuste via variável `ZBX_PROXYOFFLINEBUFFER` no serviço do proxy. Faça este exercício em cada versão (6.0, 7.0, 8.0) e compare.

## 5. Comandos úteis

```bash
docker compose ps
docker compose logs -f --tail=100 proxy-ativo
docker compose exec proxy-ativo zabbix_proxy -V | head -1
docker compose exec zabbix-server zabbix_server -V | head -1
docker images | grep zabbix

# Forçar nova leitura de config no proxy sem reiniciar
docker compose exec proxy-ativo zabbix_proxy -R config_cache_reload

# Limpar tudo e recomeçar o lab
docker compose down -v
```

## 6. Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Proxy ativo não aparece com *Last seen* | `ZBX_HOSTNAME` diferente do *Proxy name* cadastrado (diferencia maiúsculas) |
| Proxy passivo nunca conecta | Endereço/porta da interface errados no cadastro, ou `ZBX_SERVER_HOST` do proxy não inclui o server |
| Host com ZBX vermelho | `ZBX_SERVER_HOST` do agent não aponta para o proxy, ou interface do host sem DNS correto |
| Server não sobe após trocar tag | Banco ainda migrando; veja `docker compose logs zabbix-server`. Não interrompa a migração |
| Dados do proxy ignorados pelo server | Proxy mais novo que o server, ou mais antigo que a LTS anterior |
| Tag não encontrada no `pull` | Confira o nome exato no Docker Hub (`zabbix/zabbix-server-pgsql`, etc.) |

## 7. Próximos passos para evoluir o lab

- Trocar SQLite por MySQL/PostgreSQL no proxy e comparar o comportamento no upgrade.
- Adicionar **grupo de proxies** (proxy groups, disponível a partir do 7.0) com 2 proxies e testar failover.
- Criptografia PSK entre proxy e server (`ZBX_TLSCONNECT`, `ZBX_TLSACCEPT`, `ZBX_TLSPSKIDENTITY`, `ZBX_TLSPSKFILE`).
- Automatizar a atualização num script ou pipeline, com checagem de versão antes e depois.
- Commitar cada exercício num branch para comparar os diffs do `.env`.

## Referências

- Upgrade: https://www.zabbix.com/documentation/current/en/manual/installation/upgrade
- Compatibilidade de versões: https://www.zabbix.com/documentation/current/en/manual/appendix/compatibility
- Imagens Docker: https://hub.docker.com/u/zabbix
- Instalação via containers: https://www.zabbix.com/documentation/current/en/manual/installation/containers
