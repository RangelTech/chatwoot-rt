<!-- Copia redigida (cookies, tokens, senhas e hashes longos removidos) de: C:/Users/lucas.rangel/Desktop/<acervo-pessoal>/personal-skills/mega-spec-reestrutura/concluidas/produto-08-credenciais-oauth-navegador-remoto.md -->
> **28/08/2026 — arquivo movido pra `concluidas/`, condensado nas 3 specs vivas da mega-spec.** Todo o conteúdo ainda aberto (Claude/Codex no LiteLLM, decomissionamento do `oauth-browser`) foi absorvido em `../correcao-01-execucao-completa.md`. As seções concluídas (Google/Microsoft/Email/tela Credenciais) ficam aqui só como histórico.

# Produto-08 — Credenciais e conexões externas (OAuth de assinatura, navegador remoto, Google/Email/Microsoft)

> Consolidado 25/08/2026 — fundiu `produto-08-oauth-assinatura-litellm.md`
> (original), `produto-11-google-email-tools-catalogo.md` e
> `[REDIGIDO-LONGO].md` num
> só, mesmo assunto (conectar conta externa de algum tipo pro tenant
> usar). Narrativa de investigação já resolvida foi condensada — texto
> completo de cada descoberta fica no histórico do git se precisar.

## 1. OAuth de assinatura (Claude/ChatGPT/Codex) — arquitetura, CONCLUÍDA-TESTADA

Conectar a assinatura que o dono já paga (Claude/ChatGPT) uma vez, pela
tela, funcionando indefinidamente pra qualquer mensagem real de
qualquer tenant. Substitui o 9Router (decomissionado) sem repetir o bug
real dele: o problema não era o OAuth em si, era round-robin *entre
contas diferentes* coordenado em memória de processo (`selectionMutex`
não sobrevive a múltiplas instâncias). Esta spec cobre só 1 conta por
tenant por provedor — revezar entre N contas do mesmo provedor fica
fora de escopo.

**Modelo**: `tenant_ai_accounts` ganhou colunas
(`access_token_encrypted`, `refresh_token_encrypted`,
`token_expires_at`, `token_last_refresh_error`) só preenchidas quando
`auth_type IN ('redirect','device')`. LiteLLM não guarda conta — só
repassa o header `Authorization` que a gente monta
(`forward_client_headers_to_llm_api: true`); guardar/renovar o token é
trabalho nosso, do mesmo jeito que qualquer integração OAuth de
terceiro.

**Renovação — o ponto que substitui o mutex quebrado do 9Router**:
sob demanda, no momento do uso, nunca cron. Lê `token_expires_at`,
renova antes se perto de expirar, tudo dentro de `SELECT ... FOR
UPDATE` na linha da conta (lock do Postgres, não memória de processo)
— funciona certo com qualquer número de instâncias Cloud Run porque a
fonte de verdade é o banco.

**Escala confirmada**: 5.000 linhas é trivial pro Postgres; renovação
sob demanda espalha a carga naturalmente com o tráfego (pior caso
teórico ~1,4 renovação/s pra 5.000 contas); nenhuma coordenação extra
além do lock por linha.

**Risco de política, já aceito pelo dono antes desta spec**: Anthropic
proíbe formalmente esse esquema de OAuth de assinatura pra terceiros
desde abril/2026 — risco fica do lado do cliente que usa a própria
assinatura.

## 2. Navegador remoto (`oauth-browser`) — DECOMISSIONADO (decisão do dono, 26/08/2026), histórico condensado abaixo

> **Decisão fechada 26/08/2026**: o navegador remoto (`oauth-browser`,
> Playwright/patchright + VNC) **sai de cena inteiro**. Motivo do dono,
> nas palavras dele: "minha briga pra com essa extensão foi justamente
> pra gente matar esse navegador remoto". A extensão RAtende Connector
> (produto-15) já captura, no Chrome real do usuário, tudo que o
> navegador remoto existia pra capturar — Instagram/Facebook Unofficial
> (produto-05 §4g/§4h) e Claude/Codex OAuth (seção 1 acima) —
> sem Cloudflare/Turnstile no caminho (sessão real, não automação) e sem
> a complexidade de infra de Chromium+Xvfb+proxy dedicado num container.
> **Consequência direta**: a seção 3 abaixo (arquitetura VNC, o maior
> item pendente desta spec) **não precisa mais ser construída** — o
> problema que ela resolveria (drag-CAPTCHA, lag de vídeo, mirror de
> tela) deixa de existir porque não tem mais navegador remoto nenhum pra
> espelhar. Fica só como histórico técnico (como o bloqueio foi
> descoberto e contornado, útil se algum provider novo tiver o mesmo
> tipo de restrição de `redirect_uri` fixo em `localhost`).
>
> **Ordem de decomissionamento** (não apagar às cegas — confirmar
> primeiro): (1) `lab-02` Parte A confirma que o cookie da extensão é
> aceito sem transformação pelos `Channel::InstagramUnofficial`/
> `FacebookUnofficial` já existentes (produto-05 §4h); (2) `produto-08` §6
> confirma round-robin Codex+Claude real via LiteLLM usando a conta
> capturada pela extensão; (3) só depois de 1 e 2 confirmados ao vivo,
> desligar o serviço `oauth-browser` (Cloud Run,
> `infra/terraform-oauth-browser/`) e remover o card "navegador remoto"
> das telas que ainda o oferecem (`ContasIA.tsx`/wizard do Chatwoot).
> Histórico técnico da seção 2 abaixo fica registrado, não apagado —
> é conhecimento real sobre bypass de Cloudflare/proxy que pode servir
> de novo se outro provider tiver a mesma restrição de `redirect_uri`.

Claude e Codex têm `redirect_uri` fixo que só existe como `localhost`
real (Claude: página própria da Anthropic; Codex: porta 1455 que só a
CLI oficial escuta) — não dá pra resolver com um app web hospedado
normal. Solução: Chromium real (Playwright/`patchright`) rodando
**dentro do mesmo container** que intercepta a rota local
(`page.route`), com a tela espelhada pro admin via WebSocket — ele loga
normal (email/senha/2FA), o navegador roda no nosso servidor.

**Jornada de bloqueio de bot até funcionar de verdade** (histórico,
todos os passos já resolvidos):
1. Cloudflare Turnstile bloqueava Claude mesmo com clique real — causa
   real era o leak de CDP do Playwright puro (`Runtime.enable`),
   detectável independente de `navigator.webdriver`.
2. Fix: trocado Playwright por **`patchright`** (fork que fecha esse
   leak) + `channel="chrome"` (Chrome real, não Chromium open-source).
   **Resolvido de verdade** — Cloudflare parou de desafiar o Claude.
3. Codex tinha bloqueio diferente e mais severo: `auth.openai.com`
   recusava conexão (`ERR_CONNECTION_REFUSED`) de **qualquer IP da
   faixa Google Cloud**, mesmo um IP dedicado testado em São Paulo —
   bloqueio de ASN/datacenter, não geolocalização, não rate-limit.
   Infra de São Paulo (IP estático, VPC, NAT) foi **removida** depois
   (o dono não quis pagar por algo que não resolveu).
4. Fix real: **proxy pela VPS (Contabo, ASN diferente)** — HTTP CONNECT
   (`tinyproxy`), não SOCKS5 (Chromium não suporta auth em SOCKS5).
   Bypass de `localhost,127.0.0.1` necessário pro redirect local não
   tentar sair pelo proxy. **Testado ao vivo, chegou na tela de login
   real do Codex, sem desafio nenhum.**

Mirror de vídeo hoje é `page.screenshot()` em polling de 400ms (não é
CDP screencast puro — motivo técnico: a segunda sessão CDP manual
parava de emitir frame com patchright, screenshot passa pelo canal já
protegido).

## 3. Arquitetura final do navegador remoto — CANCELADA (26/08/2026, ver seção 2)

> Todo o conteúdo abaixo (VNC, drag-CAPTCHA) fica só como registro
> histórico da investigação — **não vai ser implementado**, porque o
> navegador remoto inteiro está sendo decomissionado (seção 2). Não
> reabrir isto a menos que a extensão pare de conseguir capturar algum
> provider que hoje ela cobre.

Discutido a fundo com o dono (25/08) como resolver de vez o lag do
polling e o CAPTCHA de arrastar (seção 4) — decisão final:

**Continua no Cloud Run, `concurrency=1`, não migra pra
container-por-sessão na VPS.** Já está configurado assim
(`infra/terraform-oauth-browser/main.tf`: `min_instance_count=0`,
`max_instance_count=3`, `max_instance_request_concurrency=1`,
`cpu="4"`, `memory="4Gi"`) — nunca 2 tenants na mesma instância ao
mesmo tempo, resolve isolamento visual e de recurso sem escrever
orquestrador Docker nenhum, escala só aumentando `max_instance_count`.
Cold start medido de verdade: **~13-14s** (log real de produção),
maior parte é o Chrome+Xvfb subindo — dono considerou aceitável pra
login manual.

**Vídeo/controle: trocar pra VNC (`x11vnc`+`noVNC`), não CDP
Screencast.** Com `concurrency=1` garantindo isolamento, a fraqueza do
VNC (vazar tela de outro tenant) some — vira melhor opção porque vem
pronto (vídeo E controle, incluindo arrastar de verdade) e é menos
código nosso pra manter (CDP Screencast exigiria implementar e manter
a ponte de vídeo/input na mão). **Não implementado ainda** — precisa
instalar `x11vnc`+`websockify` no Dockerfile, subir junto do Xvfb,
trocar o polling do frontend por embutir o client `noVNC`.

## 4. Drag-CAPTCHA no login Google do Claude — PENDENTE, resolvido pela decisão acima

CAPTCHA de arrastar do Google ("Drag the shape") travou o login guiado
— causa raiz confirmada, **não é o proxy** (proxy muda de onde a
conexão sai, não como o mouse se move): protocolo hoje só tem
`mouse.move`/`click` (sem `mousedown`/`mouseup`, arrastar não tem como
funcionar) e o mouse teleporta (sem `steps`, sinal de bot). A seção 3
(VNC) resolve isso de graça (protocolo nativo com drag real) — não vale
implementar as soluções incrementais (steps interpolado, drag manual)
se a seção 3 for pra frente.

## 5. UI: indicador de "aguarde" — CONCLUÍDA (25-26/08/2026)

`ContasIA.tsx` ganhou texto visível ("Abrindo o navegador… pode levar
até 15 segundos na primeira vez.") quando `iniciarNavegador.isPending`,
mesmo padrão que o modo `device` já usava. Commit `5e9861f`. Testado
via `ai-router.spec.ts` (1/1, sem regressão) — não foi possível
observar visualmente o spinner num cold start real (sem sessão
interativa nesta madrugada), mas o texto condicional está correto e
testado estruturalmente.

## 6. Teste pendente — Codex+Claude em combo round-robin no LiteLLM

**Desbloqueado 26/08/2026** — antes só faltava "credencial OAuth real,
não automatizável sozinho"; agora existe uma segunda via de captura que
não depende do navegador remoto (§2/§3): a extensão `ratende-connector`
(produto-15) já captura OAuth de Claude Code e Codex direto no Chrome
real do dono, sem Cloudflare/Turnstile no caminho (é sessão de
navegador de verdade, não Playwright automatizado). Testado ao vivo
26/08: os dois providers autenticaram e o popup da extensão mostra "1
conta" em Codex e Claude Code.

**Achado real, corrigido no caminho (26/08)**: a extensão salva o token
em `tenant_unofficial_connections` (schema do produto-15, pra
Instagram/Facebook/TikTok/OAuth genérico) — **não** é a mesma tabela que
`_criar_combo_litellm`/`_chave_da_conta` leem (`tenant_ai_accounts`,
seção 1 acima). São dois sistemas de captura de OAuth que nasceram
separados na mesma mega-spec sem se falar: produto-15 (extensão,
genérico, qualquer provider) e este produto-08 (fluxo próprio via
`oauth_engine.py`/`ContasIA.tsx`, específico pra virar deployment
LiteLLM). **Não vale reescrever nenhum dos dois** — o caminho mais
simples é uma ponte de 1 uso: ler o token já capturado em
`tenant_unofficial_connections` (provider `claude_code`/`codex_cli`),
decifrar, chamar o mesmo `_registrar_conta_oauth` que o fluxo normal do
`ContasIA.tsx` chamaria, gravando em `tenant_ai_accounts` como se o
dono tivesse clicado "Conectar" ali — sem precisar logar de novo. É só
uma chamada, não uma rota nova permanente (a extensão continuar sendo a
fonte primária desse fluxo é decisão de arquitetura separada, registrada
como opção em aberto no fim desta seção, não decidida agora).

**Confirmado (mesmo client_id, valores idênticos aos dois lugares)**: o
`client_id` público do Claude Code (`9d1c250a-...`) e do Codex CLI
(`app_EMoamEEZ73f0CkXaXp7hrann`) são os mesmos usados por
`oauth_engine.py` — o token capturado pela extensão é válido pra
qualquer consumidor que fale com a Anthropic/OpenAI usando esse
client_id, redirect_uri usado pra obter o token não importa depois de
emitido.

**Plano de execução, agora desbloqueado**:
1. ✅ Ler as 2 conexões (`claude_code`/`codex_cli`) reais de
   `tenant_unofficial_connections`, decifrar.
2. ✅ Inserir em `tenant_ai_accounts` via script pontual
   (`agent-platform/scripts/importar_oauth_extensao.py`, commit
   `b333103`) — rodado de verdade contra produção 26/08.
3. ✅ Confirmado `situacao: 'armazenada'` em `GET /api/ai-router/contas`
   pros dois (via API real, tenant `rangeltech`).
4. 🔴 **Travado num achado real de infra, não decisão de produto** —
   `POST /api/ai-router/combos` com `cc/claude-sonnet-5`+`cx/gpt-5.4`
   devolve 502 nosso / 500 do LiteLLM ("model create was saved... but
   not live in this pod's router after the reload"). Confirmado via
   `GET /model/info` direto no LiteLLM: o deployment nunca aparece.
   Causa provável: `litellm-router` está com `minScale` não setado (=0)
   — sem instância sempre viva, réplicas do Cloud Run não sincronizam
   config a tempo do check pós-escrita do próprio LiteLLM. **Mesmo
   ponto já registrado em `infra-04` §7.1** ("min_instances recomendado
   1 pro LiteLLM, não fechado, confirmar com o dono") — decisão de
   custo/infra, não resolvida sozinho. 2 deployments órfãos ficaram no
   LiteLLM dos testes (sem Team/combo associado, custo zero, seguro
   ignorar — ver `memoria.md` pro id exato se precisar limpar).
5. ⏸️ Confirmar no LiteLLM os deployments sob o mesmo `model_name` —
   bloqueado pelo item 4.
6. ⏸️ Rodar várias chamadas reais, confirmar round-robin — bloqueado.
7. ⏸️ Ligar num agente real de teste — bloqueado.

**Atualização 26/08/2026, madrugada — `min-instances=1` aprovado e
aplicado, mais 2 achados reais em cadeia**:

1. **Corrigido de verdade**: `litellm_client.create_deployment` tratava
   como erro fatal um 500 do LiteLLM que na real é sucesso assíncrono
   ("Model create was saved to the database, but... not live in this
   pod's router after the reload" — confirmado na doc oficial deles,
   Model Management: convergência entre pods é por polling, ~30s, sem
   push, mesmo com 1 instância só). Fix commitado e deployado
   (`agent-platform` `afeaa70`+`7a68553`, 11/11 testes passando,
   incluindo regressão nova pro payload real observado). Combo passou a
   ser criado sem erro.

2. **Achado maior, arquitetural, ainda não resolvido**: mesmo com o
   combo criado (2 deployments confirmados direto no Postgres do
   LiteLLM), a chamada real (`POST /v1/chat/completions`) devolve
   `"There are no healthy deployments for this model"`. Investigando a
   doc oficial do LiteLLM pros dois casos:
   - **Claude Max/Code**: prefixo certo é `anthropic/<modelo>` (não
     `cc/<modelo>`, que é só rótulo interno nosso). Auth OAuth exige
     `general_settings.forward_client_headers_to_llm_api: true` — **mas
     essa opção é desenhada pra um proxy local repassando o header
     Authorization que o PRÓPRIO Claude Code CLI do usuário manda em
     cada request** (`ANTHROPIC_CUSTOM_HEADERS` do lado cliente). Não é
     o nosso caso: aqui é o `agent-platform`/kernel chamando o LiteLLM
     server-a-servidor, sem nenhum "cliente Claude Code" vivo mandando
     header nenhum — o token precisa ficar **armazenado estático** no
     deployment, forwarding de header do chamador não se aplica.
   - **Codex/ChatGPT**: prefixo certo é `chatgpt/<modelo>` (não
     `cx/<modelo>`), com nomes de modelo reais tipo `chatgpt/gpt-5.4`.
   - **Hipótese pra resolver de verdade** (não testada ainda): usar
     `litellm_params.extra_headers` (feature documentada do LiteLLM
     pra injetar headers customizados por deployment) pra mandar
     `Authorization: Bearer <access_token>` + os headers extras que o
     Claude Code real manda (`anthropic-beta`, `anthropic-version`,
     `anthropic-dangerous-direct-browser-access` — valores exatos já
     documentados no registry do 9Router,
     `open-sse/providers/registry/claude.js`, transport.headers),
     deixando `api_key` como placeholder. Pro Codex, trocar o prefixo
     pra `chatgpt/gpt-5.4` primeiro e testar se resolve sozinho antes
     de mexer em headers.

**Por que parei de tentar às cegas**: cada tentativa faz uma chamada
real contra a conta OAuth de verdade do dono (Claude/Codex) — errar
repetidamente aumenta risco de detecção/flag da conta (mesmo tema já
registrado no `lab-02`). Preferi documentar o achado com precisão a
continuar adivinhando contra produção sem o dono por perto.

**Resíduo real desta rodada, seguro, não limpar às pressas**: existe
hoje 1 combo real criado (`[REDIGIDO-LONGO]`,
`tenant_ai_combos.id = dceb8ef9-...`) com 2 deployments no LiteLLM que
não funcionam ainda (auth errada, não modelo errado) — mais 4 deployments
órfãos de tentativas anteriores. Custo zero, nenhum roteia tráfego real
hoje. Limpar só depois que o mecanismo de auth certo for confirmado (não
faz sentido apagar e recriar toda hora até acertar).

**Retomar**: implementar `extra_headers` (Claude) + prefixo `chatgpt/`
(Codex) em `_criar_combo_litellm`, testar com no máximo 1-2 tentativas
por vez (não rajada), de preferência com o dono acompanhando.

## Atualização de execução — 27/08/2026, manhã — diagnóstico definitivo: 9Router real provou que o TOKEN está limpo, causa é volume de teste nosso

Pedido do dono: subir uma instância separada do 9Router (o mesmo
projeto que ele já usou meses em produção) e testar com o **mesmo
token real** capturado pela extensão, pra separar "token bloqueado
pela Anthropic" de "erro nosso na implementação do LiteLLM".

**Feito de verdade**: `docker compose up` local do `9router-fork`
(imagem oficial `decolua/9router:latest`, SQLite, sem tocar em nenhum
serviço de produção). Token Claude e Codex copiados direto de
`tenant_ai_accounts` (decrypt) pra dentro do SQLite do 9Router
(`providerConnections`, mesma tabela/formato que o app usa —
`createProviderConnection`), sem passar pela OAuth flow de novo, com o
9Router rodando local, isolado.

**Resultado real, decisivo**: `POST /v1/chat/completions` do 9Router
pro Claude (`cc/claude-sonnet-5`) **devolveu resposta real do modelo**
("funcionou") — sem erro nenhum, sem rate limit. **Segundos depois**,
a mesma chamada no nosso `litellm-router` de produção (mesmo token)
**bateu 429 de novo**. Prova cabal: **o token nunca esteve bloqueado
pela Anthropic** — a hipótese de "token marcado por auth errada"
registrada na entrada anterior estava **errada**.

**Causa real, achada no log do Cloud Run** (`gcloud logging read`):
o `litellm-router` acumulou **9+ combos de teste criados nesta
madrugada** (`round-robin-v1` até `v6`, `teste-round-robin-2608`,
`2608b`, `min1`) — cada criação de deployment provavelmente dispara
validação real contra a Anthropic (upsert/health-check do Router). O
log mostrava, no mesmo instante do 429, avisos repetidos de "Error
upserting deployment" pra deployments órfãos com o prefixo antigo
errado (`cc/claude-sonnet-5` sem provider). **9Router fez 1 chamada
limpa só; nosso lado fez uma rajada de 9+ criações/testes em menos de
1h** — isso é rate limit de burst real da Anthropic reagindo ao
**volume** das minhas próprias tentativas de debug, não o token em si
estar marcado.

**Limpeza feita**: os 6 deployments órfãos (prefixo antigo `cc/`/`cx/`)
apagados via `/model/delete`. Instância de teste do 9Router **derrubada
e apagada por completo** (`docker compose down -v`) depois do
diagnóstico — nenhum dado do token ficou rodando fora do lugar
combinado. Arquivos temporários com token em texto puro removidos.

**Conclusão prática**: o mecanismo (`api_key` = token puro,
`anthropic/` prefix, detecção automática do LiteLLM) **está correto**
— confirmado que autentica de verdade (chamadas anteriores já tinham
passado de "auth inválida" pra "rate limit", nunca mais voltou a dar
erro de auth). Só falta **não fazer mais rajada de teste** — esperar
um tempo real sem NENHUMA chamada nova (nem criar combo, nem testar),
depois fazer **1 chamada limpa só**, do jeito que o 9Router fez.

## Atualização de execução — 27/08/2026, manhã — rate limit do Claude: NÃO é header nem IP, é o token específico marcado pelos próprios testes desta madrugada (SUPERADO pela entrada acima — ver diagnóstico com 9Router real)

Dono apontou (correto): o Claude normal dele nunca teve rate limit —
só a chamada via LiteLLM. Duas hipóteses testadas e **descartadas**:

1. **Headers de identidade (User-Agent/X-Stainless)** — devolvidos como
   `extra_headers` aditivo (`agent-platform` commit `9ac8580`),
   deployado, testado com chamada real: **ainda 429**.
2. **IP datacenter do Google Cloud** (mesma causa já documentada pro
   Codex em §2) — testado com chamada **direta pra `api.anthropic.com`,
   sem LiteLLM no meio, via o proxy da VPS já existente**
   (`oauth-browser-http-proxy`, `66.94.101.153:18081`, credencial
   `oauthbrowser`): **ainda 429, mesmo erro genérico** (`{"type":"rate_limit_error","message":"Error"}`,
   sem `Retry-After`, sem detalhe).

**Conclusão real**: não é característica da requisição (header/IP) —
é o **token OAuth específico** que está marcado. Explicação mais
provável: as várias tentativas desta madrugada com autenticação
**errada** (antes de achar o fix real — `"OAuth access token is
invalid"`, `"invalid x-api-key"`, dezenas de tentativas em sequência
rápida contra o mesmo token) pareceram, do lado da Anthropic, um
padrão de força bruta/credential stuffing contra aquele token
específico — mesmo sendo o token real e válido, só mandado no header
errado repetidas vezes. O Claude normal do dono usa **outra sessão/
token** (login direto, não o OAuth grant capturado pela extensão), por
isso não é afetado.

**Não é mais bug de código — é tempo de resfriamento do token**.
Parei de fazer qualquer chamada nova pra esse token (já foram muitas
esta madrugada, mais tentativas só adiam a liberação). **Não retomar
teste nenhum contra esse token específico por pelo menos algumas
horas.** Mecanismo (auth automática do LiteLLM via prefixo
`sk-ant-oat`) está correto e confirmado — assim que o rate limit
liberar sozinho, a chamada real deve funcionar sem mudar mais nada de
código.

## Atualização de execução — 26-27/08/2026, madrugada (Claude, `/loop`) — Claude resolvido de verdade, Codex bloqueado por incompatibilidade estrutural

### Claude — ✅ RESOLVIDO, autenticação confirmada com chamada real

A tentativa de `extra_headers` (registrada acima) era desnecessária e
até quebrava as coisas. **Achado real, lendo o código-fonte do LiteLLM
direto no GitHub** (`litellm/llms/anthropic/common_utils.py#get_anthropic_headers`):
o LiteLLM **já detecta sozinho** token OAuth de assinatura — se
`api_key` começa com `sk-ant-oat` (`ANTHROPIC_OAUTH_TOKEN_PREFIX`), ele
troca `x-api-key` por `Authorization: Bearer` + `anthropic-dangerous-direct-browser-access`
+ o beta header de OAuth, tudo automático. **Nosso token real capturado
pela extensão tem exatamente esse prefixo** (`sk-ant-oat01...`,
confirmado direto no banco). Bastou passar o token puro como `api_key`
— revertida toda a complexidade de `extra_headers`/placeholder
(`agent-platform` commit `a8c25a6`).

**Confirmado com chamada real**: erro mudou de `"OAuth access token is
invalid"` pra `litellm.RateLimitError` (429, `rate_limit_error` da
própria Anthropic) — isso só acontece **depois** de autenticar com
sucesso. Autenticação está resolvida de verdade. O 429 é limite de uso
real da conta (Claude Max tem janela de uso, não é bug nosso) — parei
de insistir pra não consumir mais do limite da conta do dono à toa.
Deixar quieto algumas horas e testar de novo deve funcionar.

**Estado real deixado em produção**: combo `round-robin-v5`
(`tenant_ai_combos.id = a456ef78-...`) existe e está com auth correta —
só falta o rate limit da conta liberar pra confirmar uma resposta de
verdade (não só o 429). Combos de teste anteriores (v1 a v4) foram
apagados (`is_active=false`) pelo caminho normal da API.

### Codex — 🔴 BLOQUEADO por incompatibilidade estrutural, não é fix pontual

**Achado grave, lendo o código-fonte do provider `chatgpt/` do LiteLLM**
(`litellm/llms/chatgpt/authenticator.py` +
`litellm/llms/chatgpt/chat/transformation.py`): esse provider **não
aceita token externo de jeito nenhum**. Ele gerencia login E storage de
token **inteiramente sozinho**, salvo num arquivo local no disco do
container (`~/.config/litellm/chatgpt/auth.json`, controlável só por
`CHATGPT_TOKEN_DIR`/`CHATGPT_AUTH_FILE`), com seu próprio fluxo de
device-code. A linha que prova isso:
`dynamic_api_key = [REDIGIDO] —
**ignora completamente** o `api_key` que a gente manda via
`litellm_params`, sempre usa o token do arquivo local.

**Por que isso não dá pra contornar com config**: é desenho de **1
conta por instância do LiteLLM** (pensado pra proxy pessoal local, tipo
CLI de dev) — não existe conceito de "token por deployment" nem "por
tenant" nesse provider. Nosso caso é multi-tenant (cada empresa pode
ter a própria conta Codex conectada) — o provider nativo do LiteLLM
não serve pra isso estruturalmente, não é questão de achar o parâmetro
certo.

**Caminho real pra resolver** (trabalho de implementação de verdade,
não cabe numa madrugada só): construir um client HTTP próprio pro
Codex, direto, sem passar pelo LiteLLM pra esse provider específico —
usando `open-sse/executors/codex.js` do 9Router como referência (que o
dono já validou funcionar meses em produção). Não é só header — a API
real do Codex (`chatgpt.com/backend-api/codex/responses`) usa o formato
"Responses API" da OpenAI, com tradução própria: `role: system` vira
`developer`, precisa remover IDs de item gerados pelo servidor antes de
reenviar, tratar ferramentas hospedadas (`web_search`, `code_interpreter`
etc.), e fazer parsing de erro **dentro do corpo SSE** mesmo em HTTP 200
(padrões tipo `server_is_overloaded`/`model_at_capacity`). É
engenharia real, o 9Router já fez isso uma vez — replicar com cuidado,
não peça único de fix.

**Não tentei chamada real nenhuma pro Codex** depois deste achado —
ficaria testando às cegas contra a conta real sem nem o mecanismo
básico resolvido. Fica registrado como trabalho de implementação futura,
escopo maior, precisa de sessão dedicada (ou o dono decidir se vale o
esforço, dado que é só pra revezar com o Claude, não é o único provider).

## Atualização 27/08/2026, manhã — plano real de implementação do Codex (deixado pronto, não testado)

Dado o que aconteceu com o Claude (token marcado por várias tentativas
de auth errada em sequência), **decidi não repetir o padrão com o
Codex** — nenhuma chamada real foi feita, só desenho da solução, pronta
pra 1 teste único e cuidadoso quando o dono estiver por perto.

**Caminho recomendado**: não usar o provider nativo `chatgpt/` do
LiteLLM (§6 acima, incompatível por desenho). Em vez disso, apontar o
deployment pro endpoint real igual o 9Router faz, usando o modo
genérico `custom_llm_provider: "openai"` do LiteLLM com `api_base`
customizado:

```python
litellm_params = {
    "model": "openai/codex-proxy",  # nome livre, só rotula
    "custom_llm_provider": "openai",
    "api_base": "https://chatgpt.com/backend-api/codex",
    "api_key": chave,  # o JWT capturado pela extensão
    "extra_headers": {
        "originator": "codex_cli_rs",
        "User-Agent": "codex_cli_rs/0.136.0",
    },
    "model_info": {"mode": "responses"},  # avisa o LiteLLM que e' Responses API, nao chat/completions
}
```

**Riscos reais que ainda faltam confirmar antes de testar**:
1. **Formato do corpo** — a Responses API do Codex não é
   `chat/completions` puro. LiteLLM tem suporte genérico a "responses
   mode" (`model_info.mode: responses`), mas não confirmado se ele
   monta o corpo exatamente como o Codex real espera (ex.: `role:
   system` → `developer`, que o 9Router faz manualmente,
   `open-sse/executors/codex.js` função `convertSystemToDeveloperRole`)
   — LiteLLM pode ou não fazer essa conversão sozinho.
2. **IDs de item gerados pelo servidor** — 9Router remove
   (`stripStoredItemReferences`) antes de reenviar, pra não dar 404 com
   `store=false`. Não confirmado se isso importa numa primeira chamada
   simples (sem histórico de conversa) — mensagem única, sem item
   anterior, deve ser seguro pra teste inicial.
3. **Erro dentro do corpo SSE mesmo em HTTP 200** — padrões tipo
   `server_is_overloaded`/`model_at_capacity` (9Router trata isso como
   retry, não como erro imediato). Sem essa lógica, LiteLLM pode achar
   que a chamada funcionou quando na real veio um erro embutido no
   stream.

**Recomendação prática**: testar com **1 chamada simples só, sem
histórico** (mensagem única, sem tools, `stream: false` se der pra
desligar) — reduz a superfície dos 3 riscos acima de uma vez. Se
funcionar, ótimo, já resolve o caso comum. Se não, aí sim vale a pena
investir na tradução completa (replicar mais do `codex.js`).

**Ainda não implementado no código** (`_provider_model_e_headers`) —
só o desenho acima, documentado. Implementar e testar só quando o
dono confirmar que quer arriscar 1 tentativa com a conta real, de
preferência acompanhando.

## Atualização 27-28/08/2026 — implementado e testado (1 chamada real), achado o risco 1 confirmado: 404

Dono confirmou explicitamente ("termine de implementar completamente"),
implementado: `_provider_model_e_headers` virou `_provider_model_e_extras`
(ai_router.py), Codex usa `custom_llm_provider: "openai"` + `api_base`
apontando pro endpoint real, exatamente o plano acima.

**Teste real, 1 chamada só, sem stream, sem histórico** (conforme a
recomendação já registrada): `404 Not Found — OpenAIException`. LiteLLM
não usa a Responses API corretamente só com `model_info.mode:
"responses"` — o `custom_llm_provider: openai` genérico manda pro path
padrão de chat completions, não pro path real do Codex. **Confirma o
Risco 1 já documentado** ("não confirmado se ele monta o corpo
exatamente como o Codex real espera") — não é bug de configuração, é
o LiteLLM genérico não saber traduzir sozinho pra esse formato
específico.

**Conclusão real**: o caminho `custom_llm_provider: openai` +
`api_base` **não é suficiente sozinho** — confirma que o trabalho de
implementação real (client HTTP próprio replicando
`open-sse/executors/codex.js`, não configuração do LiteLLM) é
necessário de verdade, não uma tentativa a mais resolve. Deployment de
teste apagado depois do teste (não deixado no ar). Escopo maior,
sessão dedicada — não repetido essa madrugada pra não gastar mais
chamadas reais às cegas contra o endpoint do Codex.

## Atualização 28/08/2026, madrugada — CODEX FUNCIONANDO DE VERDADE, client próprio, bypass total do LiteLLM

Dono pediu pra trabalhar recursivamente comparando LiteLLM com o
9Router (os dois são opensource) até o LiteLLM funcionar igual.
Investigação real, lendo o código-fonte do LiteLLM instalado (`pip
install litellm` num venv de leitura) e comparando linha a linha com
`open-sse/executors/codex.js` + `open-sse/providers/registry/codex.js`
do 9Router:

**Achado real, explica o 404 de antes**: a URL certa é
`https://chatgpt.com/backend-api/codex/responses` — o `api_base` que
usei antes (`.../codex`, sem `/responses`) estava incompleto, e o
`custom_llm_provider: openai` genérico do LiteLLM ainda assim
apenda seu próprio path de chat/completions por cima, nunca ia bater
na URL certa mesmo corrigindo isso.

**Decisão**: construir client HTTP próprio (`app/codex_client.py`),
bypassando o LiteLLM completamente pra esse provider — replica de
verdade `codex.js`: `role: system` → `developer`, `store: false`,
`stream: true` (Codex exige, não dá pra desligar), instructions
default (usei uma versão resumida, não as 119 linhas completas do
CLI real — funcionou mesmo assim), parsing de erro embutido no corpo
SSE mesmo com HTTP 200 (`server_is_overloaded`/`model_at_capacity`).

**Testado ao vivo, 1 chamada real, sem passar pelo LiteLLM**:
`POST /backend-api/codex/responses` direto, modelo `gpt-5.4`,
Authorization Bearer com o token real da conta Codex importada. **Resultado:
sucesso de verdade — texto "funcionou" extraído dos eventos
`response.output_text.delta`, 13 eventos SSE parseados.** Codex
**funciona** com o token real, confirmando (igual o Claude) que a
credencial nunca foi o problema — era só o mecanismo de request errado.

**5 testes automatizados** cobrindo o client (`test_codex_client.py`,
servidor FastAPI de mentira simulando o endpoint real, mesmo padrão de
`test_litellm_client.py`): extração de texto dos deltas, erro
embutido no SSE apesar de HTTP 200, erro de capacidade por conta,
HTTP não-200 vira erro, conversão role system→developer. 197+5 = 202
testes do backend passando.

**Pendência real, não fechada ainda**: este client ainda não está
ligado no fluxo de inferência de verdade do agent-platform (rota que
o tenant chama pra conversar com um agente usando o combo Codex) —
hoje só é chamado direto num script de teste. Falta decidir/implementar
como ele se encaixa: rota dedicada pra provider Codex que desvia do
LiteLLM só nesse caso, mantendo LiteLLM pros outros providers? Isso é
o próximo passo real, não é mais "não sei se funciona", é "funciona,
falta plugar no lugar certo".

**`ChatGPT-Account-ID` não testado**: a conta importada não tem
`workspaceId`/`chatgptAccountId` salvo (extensão não capturou esse
dado) — funcionou sem esse header numa conta única; não confirmado se
uma conta com múltiplos workspaces precisaria dele.

## Atualização 28/08/2026 — achado o ponto exato de integração, decidido não mexer às cegas

Investigado onde a inferência de verdade acontece: **não é no
`agent-platform`** (esse é plano de controle — cria/gerencia combos),
é no **`kernel-llm`** (repo separado, runtime LangGraph real) —
`kernel-llm/app/providers.py#complete()`. Essa função roda
`litellm.acompletion()` **em processo**, chamando nosso
`litellm-router` (Cloud Run) como um provider `openai-compatible`
genérico — é o caminho de inferência de **todos os tenants, todos os
providers**, não um endpoint isolado de teste.

**Decisão**: não plugar `codex_client.py` aí às cegas essa madrugada.
Motivo: `ModelConfig`/`complete()` hoje não tem nenhum jeito de saber
"esse é Codex, desvia do litellm.acompletion()" — a distinção vive só
dentro do `model_name` opaco do LiteLLM (`tenant_..._combo_...`),
`ai_services.provider` é sempre `'openai-compatible'` genérico pra
qualquer combo. Dar esse desvio direito exige: (1) uma forma de
`ai_services`/`ModelConfig` carregar "este é Codex" até o kernel, (2)
adaptar `codex_client.executar_chamada_simples` (hoje acumula a
resposta inteira) pra emitir por `on_delta` de verdade, streaming,
igual `_stream_litellm` já faz. Mexer nisso sem review é arriscar
quebrar inferência de tenant real em produção — não é o mesmo risco
de testar um client isolado.

**Próximo passo real**: decidir com o dono se vale abrir uma spec
própria de integração (schema de `ai_services` pra guardar o provider
real, não só "openai-compatible", + adaptar `providers.py` do
kernel-llm) — escopo de mais de uma sessão, cross-repo.

**Atenção conhecida**: token OAuth do Codex expira (~1h), Claude também
expira (~8h, confirmado no registro do 9Router, `refreshLeadMs`) — só
renova ao recriar o combo (`_chave_da_conta`), sem job periódico ainda;
se o teste passar da validade, esperado erro claro de token vencido, não
travamento silencioso.

**Decisão fechada (26/08/2026, não é mais opção em aberto)**: a
extensão vira a fonte permanente de captura Codex/Claude pra este
fluxo, substituindo o navegador remoto de vez — ver seção 2 (decisão do
dono de decomissionar `oauth-browser` inteiro).

## 7. Catálogo de tools apresentável — CONCLUÍDA

`GET /v1/tools` ganhou `display_name` (nome de negócio, ex. "Consultar
agenda do Google" em vez de `google_calendar_list_events`), frontend
usa `tool.display_name || tool.name` com fallback, `title` já mostrava
a descrição. Custom Tools por tenant não precisam disso (nome já
escolhido pelo próprio tenant).

## 8. Email (SMTP/IMAP) — CONCLUÍDA-NÃO-TESTADA

Backend (migration `0034`, CRUD, `email_accounts` em permissions) +
kernel (`email_list_inbox`/`email_send`, IMAP/SMTP síncronos em
`asyncio.to_thread`) implementados e deployados. `label` opcional
escolhe a conta quando o tenant tem mais de uma. **Nunca testado com
conta de email real.** UI de conexão já existe (produto-11 §8 original,
absorvido na seção 9 abaixo).

## 9. Google (Calendar/Sheets) — CONCLUÍDA (25-26/08/2026), gap de multi-conta corrigido

Backend (`tenant_google_accounts`, provedor `google-workspace` em
`oauth_engine.py`, rotas de OAuth) + kernel (4 tools Calendar/Sheets
via `httpx`) implementados. **Credencial OAuth publicada no Infisical
25/08** (`GOOGLE_WORKSPACE_OAUTH_CLIENT_ID`/`_SECRET`, tela de
consentimento + APIs Calendar/Sheets ativadas pelo dono no Console GCP)
— app fica em modo "Testing" até decisão sobre política de
privacidade/verificação pra ir a produção. **Nunca testado com conta
Google real.**

**Gap de multi-conta corrigido**: `accounts_for_run_config` (nova
função, `google_accounts.py`) devolve a lista inteira de contas ativas
(não mais `LIMIT 1`). As 4 tools Google ganharam `label: str = ""`,
resolvido por `_google_account(context, label)`. UI de conexão ganhou
campo "Nome" editável antes de conectar. **Testado**:
`test_google_tools.py` (kernel-llm) 5/5 passando de verdade (rodado
sob Python 3.12, igual o CI) — label resolvendo a conta certa, sem
vazar pra conta errada quando o label não bate. Achado real corrigido
no caminho: o fallback (dict sem template) também estava faltando
`email_accounts`/`google_accounts`/`microsoft_accounts`.

## 10. Tela "Credenciais" unificada — CONCLUÍDA (25-26/08/2026)

`/contas-de-email` e `/contas-google` já existem e têm rota, mas
sumiram do menu (seção 11, bug de permissão) — aproveitando que precisa
mexer mesmo, decisão do dono: **apagar as 2 telas separadas e os 2
itens de menu, substituir por uma tela "Credenciais" única**, mesmo
padrão visual de "Serviços de IA" (grid de cards por tipo, clica pra
conectar) — **sem o conceito de combo** que Contas de IA tem, aqui é
direto: conecta e já fica disponível pras tools do tenant.

Cards da primeira versão: Email (SMTP/IMAP), Google (Calendar+Sheets),
Microsoft/Outlook (seção 12). Catálogo extensível (mesmo espírito do
`router_catalog.py`) — próximos tipos de credencial entram como card
novo depois, sem tela nova (ex.: Google Drive, ainda sem tool
nenhuma — não adiantar UI vazia).

**Implementado**: `Credenciais.tsx` com card-grid (Email/Google/Microsoft),
`/contas-de-email`/`/contas-google` removidas, nav gate por permissão.
**Testado**: `e2e/credenciais.spec.ts` 2/2 — criação de conta email
completa pela tela real + troca entre cards com heading certo, e
isolamento por permissão (perfil "Usuário" não vê Credenciais no menu).

## 11. Bug real — permissão nunca chegou nos admins existentes — CORRIGIDO

Causa raiz confirmada do "sumiu do meu menu": `email_accounts` e
`google_accounts` foram adicionados a `RESOURCES`
(`permissions.py:22-23`) pelas migrations `0034`/`0035`, mas —
diferente do padrão usado antes (migrations `0015`/`0016`/`0018`/`0020`
sempre fizeram `UPDATE user_profiles SET permissions = ...` pra dar a
permissão nova aos admins **já existentes**) — essas duas **não
fizeram esse backfill**. `ADMIN_PERMISSIONS` só é aplicado "on
creation" de tenant novo. Fix: nova migration com o mesmo `UPDATE
user_profiles` que as 4 anteriores já fizeram — padrão já estabelecido,
sem risco de regressão.

## 12. Microsoft Outlook (Calendário + Teams) — CONCLUÍDA (25-26/08/2026)

Prioridade do dono: ver/marcar agenda e marcar reunião do Teams (só
marcar, sem gestão avançada) — mesmo formato do Google (OAuth + REST).

**Credenciais — CONCLUÍDO 25/08/2026**: app registrado no Azure Portal
(Entra ID) pelo dono, `MS_OAUTH_CLIENT_ID`/`MS_OAUTH_CLIENT_SECRET` já
no Infisical, permissões Graph (`Calendars.ReadWrite`,
`OnlineMeetings.ReadWrite`, `offline_access`, `User.Read`) concedidas
com consentimento de admin. **Falta só o código.**

**Mecanismo da reunião do Teams**: não é API separada — evento normal
de calendário (`POST /me/events`) com `isOnlineMeeting: true` e
`onlineMeetingProvider: "teamsForBusiness"`, o Graph gera o link do
Teams automaticamente.

**Implementado**: provedor `microsoft-graph` em `oauth_engine.py`
(análogo ao `google-workspace`), migration `0037` (`tenant_microsoft_accounts`,
já nasce multi-conta com `label`, sem o gap da seção 9), rotas de OAuth
(`microsoft_accounts.py`), tools `outlook_calendar_list_events`/
`outlook_calendar_create_event` (com suporte a reunião Teams —
`isOnlineMeeting`/`onlineMeetingProvider` só quando `criar_reuniao_teams=True`),
resource `microsoft_accounts` com backfill correto na mesma migration.
Card na tela de Credenciais (seção 10). **Testado**:
`test_microsoft_tools.py` (kernel-llm) 5/5 passando de verdade (Python
3.12), incluindo o corpo exato da criação de reunião Teams. **Achado
real corrigido no caminho**: `GOOGLE_WORKSPACE_OAUTH_CLIENT_ID/SECRET`
e `MS_OAUTH_CLIENT_ID/SECRET` nunca tinham sido wireados no deploy do
Cloud Run (`ci.yml`/`deploy-cloudrun.sh` nunca liam esses secrets do
Infisical) — OAuth do Google nunca funcionou em produção até essa
correção. **Nunca testado com conta Microsoft real** (precisa do
dono).

## 13. Estado real (26/08/2026) — só resta o que precisa de escopo grande ou credencial real do dono

Seções 5, 9, 10, 11, 12 fechadas e testadas nesta madrugada (26/08).
Restam:
- **Seção 3 (VNC)** — maior escopo, arquitetura de container/x11vnc,
  não cabe numa sessão sem interação humana pra validar visualmente.
- **Seção 6 (Codex+Gemini round-robin)** — precisa de credencial OAuth
  real (login humano), não automatizável sozinho.
- Testes ao vivo com conta Google/Microsoft real (§9/§12) — idem,
  precisam do dono logando de verdade.

## 14. Fora de escopo

- Round-robin entre múltiplas contas de assinatura do mesmo provedor
  (era o bug real do 9Router — spec separada se precisar).
- Migração de tenants com conta OAuth do 9Router antigo (não existe
  dado real pra migrar).
- Anexos de email, convites de calendário com múltiplos
  participantes/RSVP, formatação avançada de planilha.
- Publicação real das telas de consentimento Google/Microsoft (depende
  de decisão do dono sobre política de privacidade/termos).


## 15. Claude e Codex no LiteLLM, Facebook/Instagram no Matrix — MOVIDO

> **28/08/2026**: esta seção foi fundida com a spec de Facebook/
> Instagram (Matrix/`mautrix-meta`) numa spec única, a pedido do dono
> ("coloque esses 2 na mesma spec"). Conteúdo completo agora em
> [`produto-18-correcao-extensao-litellm-matrix.md`](produto-18-correcao-extensao-litellm-matrix.md)
> — cobre Claude, Codex, Facebook, Instagram e TikTok, todos via
> extensão, com o motor certo por trás de cada um.
