<!-- Copia redigida (cookies, tokens, senhas e hashes longos removidos) de: C:/Users/lucas.rangel/Desktop/<acervo-pessoal>/personal-skills/mega-spec-reestrutura/correcao-01-execucao-completa.md -->
# Correção-01 — spec de execução (tudo que já dá pra construir agora, sem depender de ninguém de fora)

> **Spec viva, única, de execução** — a mega-spec foi condensada
> (28/08/2026) em 3 documentos: esta (execução), `estudo-01-pesquisa-e-bloqueios-externos.md`
> (pesquisa/bloqueios externos) e `qa-03-suite-completa-ponta-a-ponta.md`
> (teste). Todo o resto (`produto-05`, `produto-07`, `produto-08`,
> `qa-01`, `qa-02`, `lab-01`, `lab-02`, `tiktok-dm-estudo-completo.md`)
> foi movido pra `concluidas/` — não apagado, cada um com ponteiro no
> topo dizendo pra onde o conteúdo ainda aberto foi.
>
> §1-6 abaixo (Claude/Codex/Facebook/Instagram/TikTok via extensão)
> fundem o que antes eram `produto-08` §15 + a spec separada de
> Matrix/mautrix-meta, a pedido do dono ("coloque esses 2 na mesma
> spec"). §7-8 são itens menores de `produto-05`/`produto-07`/UI,
> absorvidos aqui por serem igualmente executáveis agora, sem
> depender de ninguém de fora.
>
> **Isto é só spec — nada abaixo foi implementado.** Execução só
> depois do "bora pra dev".

## 1. Visão geral — arquitetura unificada

```
                    Tela de conexões (frontend, uma só pra tudo)
                              │  usuário clica "Conectar" numa das 5 opções
                              ▼
                    Extensão (RAtende Connector) é chamada
                              │
              ┌───────────────┴────────────────┐
              │                                 │
      Claude / Codex                  Facebook / Instagram / TikTok
      (captura token OAuth)           (captura cookie de sessão)
              │                                 │
              ▼                                 ▼
    tenant_ai_accounts (ponte automática)   tenant_unofficial_connections
              │                                 │
              ▼                                 ▼
    LiteLLM CustomLLM                  Matrix + mautrix-meta (FB/IG)
    (motor: litellm-router)            ou HTTP direto (TikTok, quando
              │                         o endpoint de DM for achado)
              ▼                                 ▼
         Combo/inferência                  Chatwoot (via beeper/chatwoot,
         (agente do tenant)                 só FB/IG — TikTok é outro
                                             caminho, ver §5)
```

**Regra geral pra todo mundo (Claude/Codex/Facebook/Instagram/TikTok)**:
1. Nunca mais captura manual fora do fluxo do site — clicar "Conectar"
   na tela de conexões sempre dispara a extensão.
2. Extensão sempre captura o **máximo de informação possível** do
   cookie/token (jar completo, não só os campos mínimos) — quanto mais
   dado original, mais fiel a sessão fica pro motor de destino
   (LiteLLM ou mautrix-meta) usar.
3. Ponte extensão → tabela certa é sempre **automática**, nunca script
   manual (era um problema real do fluxo Claude/Codex, corrigido aqui;
   aplica pro resto também).

## 2. Frontend — canal da extensão (não é 1 tela unificada)

Hoje as telas estão espalhadas e inconsistentes: `ContasIA.tsx`
(cadastro de IA) ainda abre o navegador remoto antigo pra Claude/Codex;
Facebook/Instagram/TikTok não têm tela nenhuma dedicada (só a extensão
sozinha, sem nenhum site chamando).

**Correção de escopo (28/08, decisão do dono)**: eu tinha desenhado
isso como 1 tela "Conexões" única no `agent-platform` cobrindo os 5
providers — **errado**. Divisão real:

- **Claude/Codex ficam no `agent-platform` (`ContasIA.tsx`)** —
  assinatura de IA, não é rede social, faz sentido estar junto do
  resto da configuração de IA do tenant.
- **Facebook/Instagram/TikTok NÃO entram no `agent-platform`**. A UI
  de conexão desses 3 fica no **wizard de criação de inbox do
  Chatwoot** (`chat.rangeltech.net`), igual o plano original do
  produto-05 §4h (spec arquivada): combobox de conexões já
  capturadas pela extensão, direto na tela onde o usuário já cria um
  inbox — não faz sentido duplicar isso numa tela separada no site
  de agentes de IA.

O mecanismo de canal (`externally_connectable` + `onMessageExternal`)
é o mesmo pros dois casos, só muda QUEM chama (agent-platform pra
Claude/Codex, chatwoot-rt pro resto). Confirmado que a extensão usa
`externally_connectable` (manifest V3, `host_permissions`/
`externally_connectable` já incluem `ia.rangeltech.net`/
`chat.rangeltech.net`) + `chrome.runtime.onMessageExternal` no
background (`src/background/index.ts`). `window.postMessage` que eu
tinha escrito antes não existe no código, estava errado.

**Feito (28/08)**: handler real em `onMessageExternal` — mensagem
`{type: "iniciar_conexao", provider: "..."}` dispara
`iniciarCapturaCookie`/`iniciarOAuth` (mesmas funções que o clique "+"
do popup já chama), responde `{ok: true}` assim que inicia (não espera
o resultado — quem chamou consulta a própria API depois). Testado
(`tsc --noEmit`, `npm run build`, ambos limpos), commitado e
publicado (`ratende-connector` commit `b3ef9f4`). ID da extensão
(calculado a partir da chave pública fixa do manifest, estável entre
builds): `ndamceimnbinifibkmegcfhidgjamiaf`.

**Pendente**:
1. `agent-platform/frontend/src/components/ContasIA.tsx` — trocar
   `usaNavegadorEspelhado` (fluxo do navegador remoto antigo, `Claude`/
   `Codex`) por `chrome.runtime.sendMessage("ndamceimnbinifibkmegcfhidgjamiaf", {type: "iniciar_conexao", provider: "claude"|"codex"})`,
   depois consultar `/ai-router/contas` até a conta aparecer (mesmo
   padrão de `refetchInterval` que a tela já usa pro provisionamento).
2. `chatwoot-rt` — wizard de criação de inbox ganha combobox de
   conexões Facebook/Instagram/TikTok já capturadas pela extensão
   (chama `GET /api/unofficial-connections` do agent-platform via
   ponte servidor-a-servidor, token de serviço — mesmo desenho do
   produto-05 §4h arquivado) + botão "capturar nova" chamando o mesmo
   canal `iniciar_conexao`. Ainda não iniciado — só faz sentido depois
   de §4 (Matrix) estar rodando de verdade, já que é o motor que vai
   consumir essas conexões.

## 3. Claude e Codex — dentro do LiteLLM de verdade (não paralelo)

### 3a. Codex — IMPLEMENTADO E TESTADO AO VIVO (28/08/2026)

**Feito de verdade, não é mais spec.** `litellm.llms.custom_llm.CustomLLM`
era mesmo o mecanismo certo — `litellm-router/custom_provider.py`
(`CodexCustomLLM`, registrado via `litellm_settings.custom_provider_map`
no `config.yaml` do repo) roda **dentro** do Router de verdade.
`litellm-router` ganhou `Dockerfile` próprio (antes era só a imagem
oficial pura) + pipeline de deploy novo (`.github/workflows/deploy.yml`,
não existia nenhum workflow nesse repo até agora).

**2 achados reais testando localmente, antes de ir pra produção**:
1. `custom_provider_map` vai em `litellm_settings:` no `config.yaml`,
   **não** em `general_settings:` (primeira tentativa deu "Unsupported
   provider" mesmo registrado — corrigido lendo `proxy_server.py` linha
   por linha até achar o loop certo).
2. **Model não pode vir como `"codex-direct/gpt-5.4"` (string com
   prefixo)** — `get_llm_provider()` do LiteLLM só reconhece
   prefixo/model pra provider NATIVO já conhecido, não olha
   `litellm._custom_providers` na hora de splitar a string (dava "LLM
   Provider NOT provided"). Corrigido: `custom_llm_provider` como
   **campo separado** em `litellm_params`, `model` só com o nome puro
   (`"gpt-5.4"`).

**Teste real, ponta a ponta, local, com o token real de uma conta
Codex importada**: `POST /v1/chat/completions` (não-stream E stream)
através do LiteLLM Router (não client direto) — **sucesso genuíno nos
dois**, "funcionou" batendo de volta pela mesma engine que os outros
providers usam (`custom_provider.py`, linha do traceback confirmando
que o handler real foi acionado). Deployments de teste apagados,
containers locais derrubados depois.

`ai_router.py#_provider_model_e_extras` já atualizado pro caminho novo
(`custom_llm_provider: "codex-direct"`), caminho antigo quebrado
(`custom_llm_provider: "openai"` genérico, `_CODEX_API_BASE` sem
`/responses`) removido. 203/203 testes + lint passando.

**CONFIRMADO EM PRODUÇÃO (28/08/2026)**: pipeline de deploy do
`litellm-router` rodou 100% verde (2 bugs de infra achados e
corrigidos no caminho: versão do Terraform desatualizada copiada de
outro repo, `github-deployer` sem permissão de IAM em Secret Manager
— concedida só nos 3 secrets específicos, não projeto inteiro). Teste
real feito **direto em produção**, token real, `/v1/chat/completions`
através do LiteLLM Router de verdade: **"funcionou"**. Deployment de
teste apagado depois.

**Falta só**: ponte automática (§3c) já feita e testada — Codex está
100% pronto ponta a ponta, exceto o botão "Conectar via extensão" no
frontend (§2, ainda não implementado) e o handler real da extensão
(hoje só responde `ping`).

### 3b. Claude — correções testadas (28/08/2026)

1. **`?beta=true` na URL — TESTADO, INVIÁVEL via config.** Confirmado
   empiricamente (mock de `httpx.Client.send`, `litellm.completion()`
   real): LiteLLM monta a URL final com concatenação simples
   (`api_base + "/v1/messages"`), sem tratar query string — qualquer
   `?beta=true` em `api_base` vira URL quebrada
   (`https://api.anthropic.com?beta=true/v1/messages`, o `/v1/messages`
   gruda depois do `?beta=true`). Não existe `get_complete_url`
   sobrescrito pro Anthropic que trate isso melhor. **Descartado** — só
   daria pra aplicar patchando o LiteLLM de verdade (escopo do item 3
   abaixo, `CustomLLM` próprio), não vale só por essa flag isolada,
   principalmente porque era só hipótese ("pode ser redundante com o
   header `anthropic-beta` que já mandamos completo").
2. **Retry automático triplica chamadas reais** (`LiteLLM Retried: 2
   times, Max Retries: 2`, confirmado nos logs) — 9Router faz 1
   request por tentativa. Ajustar `num_retries=0` (ou com backoff
   real) no deployment Claude.
3. **Se não resolver**: hipótese de fingerprint TLS/client (Python
   `httpx` vs Node `fetch`) — só verificável testando de verdade. Se
   chegar aqui, mesmo caminho do Codex: `CustomLLM` próprio pro Claude
   com HTTP client diferente — escopo maior.

### 3c. Ponte automática (extensão → `tenant_ai_accounts`)

Hoje: extensão salva OAuth em `tenant_unofficial_connections`, e um
script manual (`importar_oauth_extensao.py`) espelha pra
`tenant_ai_accounts` — não é automático.

**Corrigir**: endpoint em `unofficial_connections.py` que, ao salvar
uma conexão `claude_code`/`codex_cli`, já chama `_registrar_conta_oauth`
na hora — sem script, sem intervenção manual.

## 4. Facebook e Instagram — Matrix + `mautrix-meta` (substitui o código Ruby/Playwright atual)

### 4a. Contexto do erro que gerou esta seção

Dono pediu, 26/08, pra usar "Matrix/mautrix". Pesquisado mal na hora,
concluído (errado) que era erro de transcrição — nunca revisitado.
Pesquisa real feita 28/08 confirma que ele estava certo:

- `mautrix-facebook`/`mautrix-instagram`: bridges reais e conhecidas,
  autenticam por cookie (Instagram: `sessionid`, `csrftoken`, `mid`,
  `ig_did`, `ds_user_id`; Facebook: `datr`, `c_user`, `sb`, `xs`) —
  descontinuadas março/2024.
- `mautrix-meta`: substituto ativo (push mais recente: hoje mesmo,
  v0.2608.0, 426 estrelas), cobre Facebook Messenger + Instagram DM no
  mesmo bridge.
- `beeper/chatwoot`: bridge real, espelha sala do Matrix num inbox do
  Chatwoot, bidirecional (ativo, últ. atualização Jan/2026).

### 4b. Por que isso substitui o código atual, não só o `oauth-browser`

`Channel::InstagramUnofficial`/`Channel::FacebookUnofficial`,
`SocialUnofficial::InstagramClient`, `NavegadorRemotoService`,
`oauth-browser` — tudo isso sai. Não é mais "mover o `oauth-browser`
pra VPS" (ideia descartada numa iteração anterior desta spec) — é
trocar o motor inteiro pelo `mautrix-meta`, que já roda 100% servidor
(nunca precisou de navegador do usuário, essa dúvida já foi resolvida).

### 4c. Modelo de container — CORRIGIDO (28/08/2026, pesquisa real): 2 processos compartilhados, não 1 por conexão

**A suposição inicial estava errada, corrigida com pesquisa real**
(documentação oficial `docs.mau.fi`/`github.com/mautrix/docs`,
confirmado que é o desenho padrão de **todo** bridge mautrix, não
específico do meta): o modelo de "1 container por conexão" veio por
analogia com a Evolution API (que de fato não suporta multi-conta num
processo só — daí a necessidade de 1 container por instância WhatsApp
lá). **O `mautrix-meta` não tem essa limitação.**

**Como funciona de verdade**: 1 processo `mautrix-meta` suporta
**múltiplas contas ao mesmo tempo** ("puppeting" — cada conta
Facebook/Instagram real vira um login dentro do mesmo bridge,
comando mandado numa sala de chat do Matrix, sem precisar de processo
novo). A única separação real é por **tipo de serviço**, não por
conexão nem por tenant: `mode: facebook` e `mode: instagram` são
configs diferentes que não podem misturar no mesmo processo.

**Modelo final, oficial**: **2 processos `mautrix-meta` fixos, pra
sempre** — 1 configurado `mode: facebook`, 1 configurado
`mode: instagram`. Todos os tenants, todas as conexões, logam dentro
desses mesmos 2 processos (login individual por conta, via comando no
bot do Matrix). Nada de provisionamento dinâmico de container, nada
de Docker API criando/destruindo processo por conexão.

**Confirmado também na pesquisa**: "bridges são desenhados como
aplicação single-instance, múltiplas instâncias do MESMO bridge não
são suportadas" — reforça que o padrão certo é escalar por conta
dentro do processo, não por processo. Postgres é recomendado (não
SQLite) pra esse cenário multi-conta ("Postgres recomendado se tiver
múltiplos usuários" — frase textual da doc oficial).

**Honestidade sobre o limite da pesquisa**: achei o *mecanismo*
confirmado e documentado oficialmente (não é invenção nem
extrapolação) — mas **não achei relato real de alguém confirmando em
produção "N contas simultâneas funcionando"**, nenhum número público
de capacidade. Achei também uma nuance importante que quase virou
confusão: existe um modo diferente, "relay bot" (várias pessoas do
Matrix compartilhando 1 conta externa só) — **não é isso que a gente
quer**. O modo certo pra este caso é "puppeting" (cada conexão loga
com a própria conta real, independente) — é o que a doc de
"múltiplos usuários"/Postgres descreve, mas vale registrar que os dois
modos existem e são coisas diferentes, pra não confundir depois.

**Validação real feita (28/08/2026, depois da decisão abaixo)**: subi
Synapse + os 2 processos `mautrix-meta` localmente (Docker, efêmero,
nunca exposto), logei a conta REAL do dono nos dois — Facebook
(`login_id=[REDIGIDO]`) e Instagram (`"Logged in as [NOME-REDIGIDO]
(104851610912965)"`, `username: lucasranngels`) — usando exatamente o
cookie que a extensão capturou depois da verificação de segurança da
Meta. Os dois conectaram, sincronizaram threads reais, criaram
portais. **O que isso confirma**: o mecanismo de login por cookie via
comando de chat (`login facebook`/`login instagram` + JSON de cookies
na sala de gerência do bot) funciona de ponta a ponta com dado real,
não só documentação. **O que isso NÃO confirma ainda**: só logei 1
conta por processo (a única que existe hoje) — a pergunta original
"múltiplas contas no MESMO processo sem conflito" continua sem teste
real dedicado, só a decisão do dono abaixo (sem limite, observar via
Grafana), que já assume que funciona. Vale revisitar quando existir
uma 2ª conta real do mesmo tipo pra testar de verdade.

**EM PRODUÇÃO DE VERDADE (28/08/2026, mesmo dia, depois do teste
local acima)**: replicado via Terraform em `vps_rt_infra` — Synapse +
`matrix-postgres` + os 2 processos `mautrix-meta` rodando na VPS,
não mais teste efêmero. Login real repetido com sucesso (mesmos
IDs de conta): Facebook `100008984204658` CONNECTED, Instagram
`104851610912965` (`lucasranngels`) CONNECTED. 3 bugs reais de infra
achados só em produção e corrigidos (detalhe completo em
memoria.md 28/08/2026 "MATRIX EM PRODUÇÃO DE VERDADE"): bind mount
aninhado virando stub vazio (corrigido movendo config pra
`/etc/synapse/`, fora de `/data`), rede `internal` sem saída pra
internet (bridges ganharam também a rede `public`), `matrix-postgres`
sem `chown 999:999` (causava corrupção silenciosa de permissão nos
arquivos internos do Postgres, healthcheck não detectava).
`oauth-browser`/`SocialUnofficial::*`/`Channel::*Unofficial` ainda
NÃO foram desligados — fazer só depois de mais confiança acumulada
(múltiplas contas reais, `beeper/chatwoot` mapeado, QA rodado).

**Decisão do dono (28/08/2026)**: adotar o modelo compartilhado (2
processos). **Sem limite de conta configurado** — nem container, nem
número parametrizado. Acompanhamento é só observação real via
Grafana; se o processo ficar pesado, decisão é aumentar a máquina
(vertical), não criar lógica de limite/particionamento agora. Se no
futuro alguma conta específica travar o processo pras outras
(problema real, não hipotético), reavaliar isolamento — não é o
desenho inicial.

### 4d. Automação de login (cookie → `mautrix-meta`, sem colar na mão)

O fluxo real do `mautrix-meta` é "humano manda comando de login numa
sala do Matrix, colando o cookie". Precisa de automação:

1. Client Matrix nosso (biblioteca de protocolo Matrix — ex.
   `matrix-nio` em Python) que, assim que o backend recebe um cookie
   novo da extensão, manda o comando de login sozinho na sala de
   gerência do bridge correspondente.
2. Cookie usado: **o jar completo capturado pela extensão**, não só o
   subconjunto mínimo documentado pelo `mautrix-meta` (pedido explícito
   do dono — "pegar o máximo de informação que o Matrix aceitar").
   Confirmar na prática quais campos extras o `mautrix-meta` aceita
   sem rejeitar (a doc só lista o mínimo obrigatório).

### 4e.0 Mapeamento de inbox — decisão do dono (28/08/2026)

**1 inbox por conexão, igual funciona hoje** (não é 1 inbox
compartilhada por tipo/serviço). Cada conta Facebook/Instagram do
tenant vira sua própria inbox no Chatwoot — o `beeper/chatwoot`
precisa mapear 1 sala-raiz do Matrix (ou 1 conjunto de salas de 1
conta puppeted específica) pra 1 inbox específica, não pra uma inbox
genérica "Facebook do tenant". Confirmar se o `beeper/chatwoot` já
suporta esse granularidade (mais provável que precise de ajuste — ver
§4e abaixo) antes de assumir que funciona pronto.

### 4e. `beeper/chatwoot` — confirmar multi-tenant antes de assumir

A documentação encontrada não deixa claro suporte nativo a múltiplos
tenants/inboxes simultâneos. Precisa ler o código de verdade (não só a
doc) antes de decidir: usar como está (1 instância por tenant?) ou
adaptar (patch pra mapear sala→inbox considerando tenant).

**Fica mais crítico com o modelo compartilhado (§4c)**: como as
contas de todos os tenants agora vivem dentro dos mesmos 2 processos
`mautrix-meta`, o isolamento entre tenants não pode depender de
"processo separado" — precisa ser garantido no mapeamento
sala-do-Matrix→inbox-do-Chatwoot (`beeper/chatwoot`) e na consulta que
lista conexões por tenant (`tenant_unofficial_connections`, já filtra
por `tenant_id`, mas confirmar que nada no bridge cruza esse limite).
Testar isso de propósito antes de considerar pronto — ver
`qa-03-suite-completa-ponta-a-ponta.md` Camada 4/9.

### 4f. Migração de histórico — política padrão: últimos 2 meses

**Decisão do dono (28/08/2026)**: ao migrar uma conexão existente pro
Matrix, trazer só as mensagens dos **últimos 2 meses** — não o
histórico completo, não começar limpo do zero. Isso vira **padrão
permanente** pra qualquer migração futura desse tipo (não é regra de
uma vez só). Aplica às conexões já existentes hoje (6 conversas/
15 mensagens Instagram, 8/8 Facebook — todas dentro da janela de 2
meses, então migram inteiras na prática).

Depois de confirmado ao vivo: desligar `oauth-browser` de vez
(`infra/terraform-oauth-browser/` sai), remover
`SocialUnofficial::*`/`Channel::*Unofficial` do `chatwoot-rt`.

## 5. TikTok — via extensão, SEM Matrix/mautrix (não existe bridge)

**Confirmado (28/08/2026)**: não existe `mautrix-tiktok` nem
equivalente no ecossistema Matrix — pesquisado, não achado. TikTok
**não entra** no fluxo Matrix/`mautrix-meta` do §4.

TikTok segue caminho próprio, já desenhado antes desta spec
(`tiktok-dm-estudo-completo.md`): extensão captura cookie completo
(já funciona), sessão autentica via HTTP direto (confirmado ao vivo),
mas o endpoint exato de ler/mandar DM ainda não foi encontrado — falta
1 captura de rede real do dono (`tiktok.com/messages`, DevTools →
Copy as cURL). Sem isso, não dá pra fechar o canal TikTok, com ou sem
Matrix.

**O que muda aqui por causa desta spec**: TikTok entra na mesma tela
de conexões única (§2), mesmo botão "Conectar" chamando a extensão —
só o motor por trás é diferente (HTTP direto, não Matrix).

## 7. Outros itens executáveis agora (absorvidos de `produto-05`/`produto-07`/UI)

Não dependem de aprovação externa nem do dono logar em nada — dá pra
fazer em paralelo com §1-6, prioridade menor.

### 7a. Ícone "Enviar" do compositor do chat — 1 linha (de `correcao-01` antigo §7, arquivado)

`agent-platform/frontend/src/pages/Chat.tsx:653` — `<Send size={18} .../>`
devia ter virado `size={20}` junto com anexo/microfone (commit `817a027`
esqueceu esse ícone especificamente). Trocar pra `size={20}`.

### 7b. WAPI/Evolution — pontas soltas de teste, sem depender de credencial de terceiro

- Evolution: medir RAM/CPU real de 1 container em uso normal por um
  tempo (não só no boot) — decide se "1 container por tenant" aguenta
  escalar como está (Grafana/cadvisor já existem, `infra-01` §9b).
- WAPI: falta só validar `GET /v1/instance/status-instance` com
  credencial real de terceiro (fora do nosso controle — registrar como
  bloqueado nesse ponto específico, não é "fazer", é "esperar
  credencial").

### 7c. Inbox não aparece pro usuário analista — investigar permissão

`Configurações → Caixas de entrada → Adicionar caixa` não aparece pra
usuário com papel de agente/analista (só pra `administrator`). Hipótese
principal: comportamento correto do Chatwoot (criação de inbox exige
admin) — confirmar com um administrador real da mesma conta antes de
tratar como bug. Se confirmado que é assim mesmo, fechar o ponto como
"não é bug"; se administrador também não vir a opção, aí sim investigar
feature flag/rota.

### 7d. Bug 409 do Assistente RAgentes — replanejamento no mesmo turno

`tenant_guide.py`: quando o modelo replaneja (`tenant_guide_plan_template`)
na MESMA resposta em que confirma (`tenant_guide_create_template_from_plan`),
a checagem de confirmação (compara `created_at` do plano contra
`created_at` da mensagem) inverte a ordem esperada e falha com 409.
Reproduzido de forma determinística. Correção sugerida (não
implementada): ajustar o prompt do agente pra reaproveitar o
`confirmation_id` anterior em vez de gerar plano novo, OU trocar a
checagem de timestamp por comparação contra a mensagem do turno atual.
Correção calma e focada — mexe em lógica de segurança anti-hallucination,
não é hotfix de madrugada.

### 7e. Teste real de provisionamento de tenant em produção (RAgentes)

A remoção do fallback local (produto-07 §8a.5) foi confirmada por
consulta real de infra, mas "provisionar tenant novo continua
funcionando" só tem prova por teste automatizado (158 testes CI) —
nenhum tenant real foi criado em produção depois da remoção pra
confirmar na prática. Falta esse teste real.

### 7f. Ocultação de recursos Premium — auditoria funcional pendente

`produto-05` §6b: flags nativos do Chatwoot existem, mas cada item de
menu/feature do dashboard precisa de auditoria funcional real — não
considerar concluído só pela existência do flag.

## 8. Ordem de execução — decidida pelo dono (28/08/2026)

**Prioridade explícita**: Claude/Codex primeiro, depois
Instagram/Facebook, resto na ordem que fizer mais sentido técnico.

1. **§2 + §3c** (frontend unificado + ponte automática) — pré-requisito
   de infra pra qualquer um dos 5 tipos de conexão, faz sentido entrar
   primeiro mesmo sendo "transversal" às prioridades do dono.
2. **§3b** (Claude — `?beta=true` + `num_retries=0`) — prioridade 1 do
   dono. Barato, testa rápido se resolve o 429.
3. **§3a** (Codex — `CustomLLM` no LiteLLM) — prioridade 1 do dono,
   junto com Claude. Depende de criar pipeline de build/deploy novo
   pro `litellm-router`.
4. **§4** (Facebook/Instagram — Matrix/`mautrix-meta`) — prioridade 2
   do dono. Escopo bem menor agora que o modelo é 2 processos
   compartilhados (§4c corrigido), não mais provisionamento dinâmico
   de container — mas ainda precisa de homeserver Matrix novo +
   automação de login.
5. **§7a-§7f** (itens menores) — podem entrar em paralelo com qualquer
   ponto acima, não competem por recurso, prioridade "resto" do dono.
6. **TikTok (§5)** — continua bloqueado até o dono mandar a captura de
   rede, independente da ordem acima.

## 9. Perguntas — respondidas pelo dono (28/08/2026)

1. **Homeserver**: usar o que o Matrix recomenda oficialmente pra
   suporte a *appservice* — **Synapse** (é a implementação de
   referência, suporte a *appservice* mais maduro; alternativas leves
   como Conduit/Dendrite têm suporte parcial/experimental a esse
   recurso especificamente).
2. **Migração de histórico**: últimos 2 meses, vira padrão permanente
   (ver §4f).
3. **Limite de recursos**: não é mais "container por conexão" (§4c
   corrigido) — a pergunta muda de "quantos containers" pra "quantas
   contas 1 processo `mautrix-meta` aguenta antes de degradar". **Dono
   decidiu (28/08, segunda rodada): sem limite configurado nenhum** —
   nem número parametrizado, nem hardcoded. Acompanhar via Grafana; se
   o processo ficar pesado, resolve na hora (aumentar máquina), não
   precisa de lógica de limite pronta de antemão.
4. **Se o processo ficar pesado**: dono compra VPS maior (escala
   vertical). Não precisa de orquestrador (Nomad/k3s) nem multi-VPS
   agora.
5. **Prioridade**: Claude/Codex → Instagram/Facebook → resto (aplicado
   em §8 acima).
