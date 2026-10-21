<!-- Copia redigida (cookies, tokens, senhas e hashes longos removidos) de: C:/Users/lucas.rangel/Desktop/<acervo-pessoal>/personal-skills/mega-spec-reestrutura/memoria.md -->
## 28/08/2026 — MATRIX EM PRODUÇÃO DE VERDADE na VPS: Facebook e Instagram logados com a conta real do dono

Replicado o que foi validado local pra `vps_rt_infra` (Terraform):
`matrix-postgres` (Postgres dedicado, 3 bancos em locale `C` —
Synapse exige, `en_US.utf8` do container quebra), `synapse`
(matrixdotorg/synapse:v1.159.0, sem federação), `mautrix-meta-facebook`
+ `mautrix-meta-instagram` (compartilhados, sem limite de conta,
decisão do dono já registrada em §4c). Segredos reais gerados
(`openssl rand`) direto pro `terraform.tfvars` (arquivo local,
gitignored) — `as_token`/`hs_token` fixos (não gerados pelo bootstrap
do bridge) pra registration.yaml e config.yaml do bridge nascerem
consistentes sem dança de bootstrap manual.

**3 bugs reais achados só em produção (não apareceram no teste
local)**, cada um corrigido no código antes de fechar:

1. **Bind mount de arquivo dentro de outro volume virou diretório
   vazio dono de root** (mesma classe de bug que tinha visto no
   Windows, mas aconteceu também no Linux real da VPS) — Docker
   materializa um stub vazio quando o mount aninhado não resolve a
   tempo, e o suspeito real é o `rt-compose-healer.timer` (roda
   `docker compose up -d` sozinho a cada minuto) correndo em paralelo
   com o `docker compose up -d` do próprio Terraform. Corrigido de
   raiz: `homeserver.yaml`/`log.config`/`registrations` do Synapse
   agora montam em `/etc/synapse/...`, um caminho **totalmente
   separado** de `/data` (que só guarda estado real: signing key,
   media) — elimina a classe inteira do bug, não só o sintoma.
2. **Rede `internal` bloqueia toda saída pra internet por design**
   (`internal: true` no compose) — os bridges `mautrix-meta`
   precisam alcançar facebook.com/instagram.com de verdade, ficaram
   com DNS quebrado ("server misbehaving") até eu adicionar a rede
   `public` também (mantendo `internal` pra falar com o Synapse).
3. **`matrix-postgres` esqueci de dar `chown -R 999:999`** (padrão já
   usado pros outros 2 Postgres do compose, `postgres` e
   `infisical-postgres` — só não copiei a linha pro novo serviço).
   Sintoma enganoso: o container ficava "healthy" (o healthcheck só
   testa `pg_isready`, que passa igual), mas falhava internamente com
   `Permission denied` em arquivos do próprio sistema Postgres
   (`global/pg_filenode.map`, `pg_logical/snapshots`) assim que
   qualquer coisa tentava usar o banco de verdade. Corrigido ao vivo
   (chown + restart, WAL redo automático recuperou sem perda) e
   adicionada a linha que faltava no `main.tf` pra nunca mais
   acontecer em redeploy.

**Login real, em produção, mesma conta do dono**:
- Facebook: `"Logged in as [NOME-REDIGIDO] (100008984204658)"`,
  `state_event: CONNECTED`, sincronizando threads reais.
- Instagram: `"Logged in as [NOME-REDIGIDO] (104851610912965)"`,
  `username: lucasranngels`, `CONNECTED`, portais reais sendo criados.

**Achado à parte sobre o fluxo de login por comando**: a sala vira
"management room" só na PRIMEIRA vez que o bot é convidado por aquele
usuário — se já existe uma DM anterior com o mesmo bot (aconteceu aqui
porque recriei a sala do Facebook depois do bug #3), salas novas
precisam do prefixo `!fb`/`!ig` em TODA mensagem, inclusive o JSON de
cookies (não só no comando `login` inicial) — sem isso a mensagem
chega no bridge mas é silenciosamente ignorada (nenhum log, nem erro).
Relevante pra quando isso for automatizado via `matrix-nio` (§4d): usar
sempre o prefixo explícito, não depender da sala ser "management room".

**Pendente real, próximo passo**: reaplicando agora (`terraform
apply` em andamento) os 2 fixes de infra acima (bug #1 e #3) de forma
permanente no código — já corrigidos ao vivo na VPS, faltava só a
IaC refletir. `beeper/chatwoot` (mapear sala→inbox) e a automação via
`matrix-nio` continuam não iniciados — próximos passos reais depois
que a infra estiver 100% estável.
