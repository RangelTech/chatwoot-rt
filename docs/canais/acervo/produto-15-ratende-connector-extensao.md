<!-- Copia redigida (cookies, tokens, senhas e hashes longos removidos) de: C:/Users/lucas.rangel/Desktop/<acervo-pessoal>/personal-skills/mega-spec-reestrutura/concluidas/produto-15-ratende-connector-extensao.md -->
# Produto-15 — RAtende Connector (extensão de navegador)

> Criada 25/08/2026, a partir de um documento de arquitetura trazido pelo
> dono (`ratende_connector_extensao_sessao.md`, elaborado com apoio de outro
> modelo) + refinamento em conversa direta. **Esta spec é só a POC da
> extensão em si — captura de cookies, autenticação, menu, empacotamento e
> download.** Não mexe no Chatwoot (`chatwoot-rt`), não mexe no fluxo VNC de
> Claude/Codex (produto-08 §2/§3), não decide ainda como o Chatwoot vai
> consumir as credenciais capturadas. Isso fica pra uma spec seguinte,
> **depois** de provar que a captura funciona de verdade.
>
> **Repo: separado, `RangelTech/ratende-connector`** (decisão do dono,
> 25/08) — não entra dentro do `agent-platform`. Motivo: toolchain
> diferente (empacota zip pra Chrome, não builda pra Cloud Run), acoplamento
> com o backend é só HTTP normal (mesmo contrato de qualquer client
> externo, não precisa compartilhar código), e já existe precedente de
> serviço isolado ter repo próprio na org (`kernel-llm`, `chatwoot-rt`,
> `vps_rt_infra` — nem tudo é monorepo; `oauth-browser` só ficou dentro do
> `agent-platform` porque ele *é* deployado no mesmo pipeline Cloud Run, o
> que não é o caso da extensão).

## 1. Objetivo e motivação

Hoje a única forma de capturar uma sessão autenticada de um provider externo
é o fluxo VNC (produto-08 §2/§3): Chromium real rodando **na nossa infra**
(Cloud Run), controlado remotamente pelo admin via WebSocket, com
`patchright`+Chrome real+proxy pela VPS pra não ser detectado como bot. Isso
resolveu Claude/Codex, mas **quebrou 2x contra o TikTok** (contexto do
navegador morre, não é timeout) mesmo com as mesmas técnicas — motivo pelo
qual o TikTok Unoficial foi confirmado inviável (`produto-05` §4g).

**Hipótese a testar**: se o login acontece no navegador **real do usuário**,
via uma extensão, nenhuma automação toca a tela de login — o sinal que faz o
TikTok (e potencialmente outros providers agressivos) detectar bot nunca é
gerado, porque não há bot ali, é o próprio Chrome do cliente. A extensão só
entra **depois** que o login humano já aconteceu, pra ler os cookies da
sessão e mandar pro backend.

**Não é substituição do VNC.** É uma frente paralela, testada sem tocar no
que já funciona (Claude/Codex). Se a POC provar que a captura funciona (o
critério de aceite desta spec), aí sim vira candidata a resolver o TikTok —
e possivelmente simplificar Facebook/Instagram Unoficial também, que hoje
dependem de recaptura manual guiada pelo dono via VNC.

## 2. Quem autentica, e por quê é mais simples que o documento original

O documento original (`ratende_connector_extensao_sessao.md`) desenha um
fluxo de **pairing token** (código de 6 dígitos, backend gera, extensão
recebe, expira em 300s) pensado pra um cenário onde a extensão não sabe
quem é o usuário. **Não é o nosso caso**: a extensão é nossa, o usuário que
vai usá-la já é cliente RAgentes/RAtende. Decisão confirmada com o dono
(25/08): **a extensão loga direto no RAgentes** (mesmo email/senha que o
usuário já usa no painel), sem pairing token nenhum.

Isso simplifica bastante:
- `POST /api/auth/login` (rota que já existe, `agent-platform/backend`) —
  a extensão manda email/senha, recebe `token` + `chatwoot_sso_url` (esse
  campo **já existe hoje** na resposta de login, usado pra SSO
  RAgentes→RAtende — a extensão só reaproveita).
- O token vai pro `chrome.storage.local` da extensão (nunca `.sync` — evita
  sincronizar credencial pela conta Google do usuário entre máquinas sem
  controle nosso). Reautentica quando expira (mesma política de sessão
  deslizante de 8h do produto-14 §3, se já estiver implementada até lá).
- Toda chamada da extensão pro backend usa esse token normal — **é o mesmo
  usuário autenticado que já usaria o painel web**, então toda a lógica de
  permissão/tenant já existente (`require()`, `resolve_target_tenant()`) se
  aplica sem nada novo.

**Nível de segurança aceito explicitamente pelo dono (25/08)**: não é
necessário nível "cofre" pra isso — a extensão só roda na máquina de quem já
é cliente autorizado do próprio tenant. Não construir camada extra de
proteção do token da extensão além do que a sessão web normal já tem.

## 3. Design visual — referência Okta Browser Plugin

O dono trouxe a extensão do Okta como referência de layout (print anexado à
conversa). Estrutura a replicar (adaptada, não copiar ícone/assets
proprietários):

```
┌─────────────────────────────────────┐
│ [logo RAgentes]  Nome do Tenant   ⚙ │  <- header: logo, nome do tenant
│                                      │     (no lugar do "avatar" do Okta),
│                                      │     ícone de engrenagem (config)
├─────────────────────────────────────┤
│                                      │
│  Abrir RAtende                  ↗   │  <- item de lista, ícone + label
│  Abrir RAgentes                 ↗   │
│                                      │
│  Logins não oficiais             ›  │  <- expande em submenu
│                                      │
└─────────────────────────────────────┘
```

Ao clicar em **"Logins não oficiais"**, o popup navega (sem sair da
extensão, é uma view interna) pra uma segunda tela:

```
┌─────────────────────────────────────┐
│ ‹ Logins não oficiais                │  <- botão voltar
├─────────────────────────────────────┤
│  Instagram                       +  │  <- provider, contagem de contas,
│    @empresa_oficial          ⋯      │     botão "+" adiciona nova
│    @empresa_secundaria       ⋯      │
│                                      │
│  Facebook                        +  │
│    (nenhuma conta conectada)        │
│                                      │
│  TikTok                          +  │
│    @empresa.tiktok           ⋯      │
│                                      │
│  Claude          em breve           │  <- v1: listado, desabilitado
│  Codex            em breve          │     (ver seção 8, mecanismo diferente)
└─────────────────────────────────────┘
```

Cada conta listada tem um menu `⋯` com **Reconectar** e **Remover** (mesmo
padrão de estados que produto-08 §9/§10 já usa pra Google/Email: nome
editável, múltiplas contas por provider).

**Paleta/tema**: reaproveitar os tokens de tema já definidos no frontend do
RAgentes (`--brand`, `--brand-soft`, `--surface-solid`, etc., mesmos usados
em `components/ui.tsx`) — a extensão deve parecer parte da mesma família
visual, não um produto à parte. Ícones: Lucide, mesmo padrão do resto do
produto (nunca ícone proprietário de outra marca).

## 4. Menu — comportamento de cada item

- **"Abrir RAtende"**: abre nova aba com a URL de `chatwoot_sso_url` (vem
  pronta da resposta de login — SSO já funciona, zero código novo do lado
  do Chatwoot).
- **"Abrir RAgentes"**: abre nova aba com `settings.public_base_url` do
  tenant (mesma URL que o usuário acessaria digitando o domínio direto).
- **"Logins não oficiais"**: navegação interna do popup (ver seção 3), lista
  os providers e contas já conectadas (`GET /api/unofficial-connections`,
  seção 6).
- **Engrenagem (⚙)**: tela simples — "Sair" (limpa `chrome.storage.local`),
  mostra versão da extensão, link "Precisa de ajuda?" apontando pro
  Assistente RAgentes (produto-07).

## 5. Fluxo de captura — passo a passo

Usando TikTok como exemplo concreto (provider de prova desta POC):

1. Usuário abre a extensão, vai em "Logins não oficiais" → "TikTok" → botão
   `+`.
2. Extensão abre `https://www.tiktok.com/login` numa aba nova (não é popup
   modal — precisa ser aba real pra qualquer 2FA/challenge funcionar
   normal, exatamente como o usuário já faz login em qualquer site).
3. Usuário faz login normal, do jeito que sempre faz (senha, 2FA, o que o
   TikTok pedir) — **a extensão não participa dessa etapa, só observa**.
4. A extensão (background service worker) monitora essa aba via
   `chrome.tabs.onUpdated`, checando periodicamente (ou ao detectar navegação
   pra fora de `/login`) se os cookies de sessão do domínio já existem
   (`chrome.cookies.getAll({domain: "tiktok.com"})`, procurando o(s)
   cookie(s) que indicam sessão autenticada — nome exato mapeado por
   provider, ver seção 8).
5. Quando detecta cookie de sessão presente, mostra uma notificação/badge na
   extensão ("Conta detectada — clique pra conectar") — **não envia nada
   sozinha**, exige clique explícito do usuário (mesmo princípio de
   consentimento do documento original, seção 10 dele).
6. Usuário clica "Conectar esta conta" (dentro do popup da extensão, aba do
   TikTok pode ser fechada nesse ponto).
7. Extensão lê os cookies relevantes (allowlist por provider, seção 8),
   monta o bundle:
   ```json
   {
     "provider": "tiktok_web",
     "label": "TikTok principal",
     "external_label": "@empresa.tiktok",
     "cookies": [{"name": "...", "value": "...", "domain": "...", "path": "/"}]
   }
   ```
8. `POST /api/unofficial-connections` (autenticado com o token da extensão,
   seção 6) — HTTPS, o payload nunca é logado (mesma regra do documento
   original seção 12: nunca registrar `cookie`/`session`/`token` em log,
   nem no backend nem na extensão).
9. Backend cifra (`crypto.py:encrypt`, mesmo mecanismo já usado pra
   token do Google/senha de email) e persiste. Devolve o registro serializado
   (sem o valor cifrado) pro popup atualizar a lista.

## 6. Backend — o que entra nesta spec

Novo em `agent-platform/backend` (mesmo repo, mesmo padrão dos módulos
`google_accounts.py`/`email_accounts.py` — não é serviço novo, é mais uma
rota):

### 6a. Migration

```sql
-- backend/migrations/00XX_unofficial_connections.sql
CREATE TABLE tenant_unofficial_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,             -- 'instagram_web' | 'facebook_web' | 'tiktok_web'
    label TEXT NOT NULL,                -- nome editável, ex. "TikTok principal"
    external_label TEXT,                -- @handle detectado, não sensível
    cookies_encrypted TEXT NOT NULL,    -- JSON dos cookies, cifrado
    status TEXT NOT NULL DEFAULT 'connected',  -- connected | reauth_required | error
    last_validated_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_tenant_unofficial_connections_tenant
    ON tenant_unofficial_connections (tenant_id) WHERE is_active;

-- Recurso de permissão novo -- backfill JÁ NESTA MIGRATION (não repetir o
-- bug do produto-08 §11, onde 0034/0035 esqueceram o backfill).
UPDATE user_profiles
   SET permissions = permissions || '{"unofficial_connections": ["view", "create", "edit", "delete"]}'::jsonb
 WHERE NOT (permissions ? 'unofficial_connections')
   AND permissions -> 'templates' @> '["view", "create", "edit", "delete"]'::jsonb;
```

`permissions.py`: adicionar `"unofficial_connections"` em `RESOURCES`.

### 6b. Rotas (`backend/app/routes/unofficial_connections.py`)

Mesmo padrão de `google_accounts.py`/`email_accounts.py`:

```
GET    /api/unofficial-connections                 lista (escopo tenant)
POST   /api/unofficial-connections                  cria (provider, label, external_label, cookies)
DELETE /api/unofficial-connections/{id}             soft-delete (is_active=false)
```

`_serialize()` **nunca** devolve `cookies_encrypted` — mesma regra que
senha/token nunca voltam em listagem hoje.

**Validação de provider**: `provider` restrito a um enum
(`instagram_web`, `facebook_web`, `tiktok_web`) — rejeita qualquer outro
valor com 400. Claude/Codex **não entram nesse enum nesta spec** (seção 8
explica por quê).

### 6c. O que esta spec NÃO decide

- Como o `chatwoot-rt` vai ler dessa tabela pra alimentar
  `channel_instagram_unofficial`/`channel_facebook_unofficial`/um futuro
  `channel_tiktok_unofficial` — é trabalho de integração pra uma spec
  seguinte (o combobox que o dono mencionou).
- Revalidação periódica do cookie (`last_validated_at`/`status` existem no
  schema, mas nenhum job/runtime usa ainda nesta spec — só ficam
  disponíveis pra quando o consumidor real for construído).

## 7. A extensão em si

### 7a. Stack e estrutura

- **Manifest V3** (obrigatório — V2 está sendo descontinuado pelo Chrome).
- Build: Vite + `@crxjs/vite-plugin` (gera `manifest.json` + bundles a
  partir de TS/React, hot-reload em dev) — mesma stack de tooling
  (Vite/TS/React) já usada no `agent-platform/frontend`, reaproveita
  conhecimento do time.
- Estrutura (raiz do repo `RangelTech/ratende-connector`):
  ```
  ratende-connector/
  ├── manifest.json
  ├── src/
  │   ├── popup/          # UI do popup (React, componentes seção 3/4)
  │   ├── background/     # service worker: monitora abas, cookies, fala com API
  │   ├── content/         # content scripts por domínio (mínimo necessário)
  │   ├── lib/
  │   │   ├── api.ts       # cliente HTTP pro backend agent-platform
  │   │   └── providers.ts # registry de providers (seção 8)
  │   └── options/         # tela de configurações (engrenagem)
  ├── icons/
  └── vite.config.ts
  ```

### 7b. Permissões (`manifest.json`)

Princípio de menor privilégio (mesmo do documento original, seção 9) —
**não pedir `<all_urls>`**:

```json
{
  "manifest_version": 3,
  "name": "RAtende Connector",
  "permissions": ["cookies", "storage", "tabs"],
  "host_permissions": [
    "https://www.instagram.com/*",
    "https://www.facebook.com/*",
    "https://www.tiktok.com/*",
    "https://SEU-DOMINIO-AGENT-PLATFORM/*"
  ],
  "externally_connectable": {
    "matches": [
      "https://ia.rangeltech.net/*",
      "https://chat.rangeltech.net/*"
    ]
  },
  "action": { "default_popup": "popup.html" },
  "background": { "service_worker": "background.js", "type": "module" }
}
```

`host_permissions` cobre só os domínios dos providers de prova + o próprio
backend (pra chamar a API sem CORS de extensão). Não pede acesso a site
nenhum fora dessa lista.

**`externally_connectable`** (pedido do dono, 25/08 — deixar já pronto pro
futuro, sem construir o lado que consome ainda): é o mecanismo oficial do
Chrome que permite que só uma página desses domínios específicos (nunca
qualquer site) chame `chrome.runtime.sendMessage(EXTENSION_ID, mensagem)`
diretamente, sem passar por `postMessage`/content script. Declarando os dois
domínios agora (`ia.rangeltech.net` = RAgentes, `chat.rangeltech.net` =
RAtende/Chatwoot) deixa a extensão pronta pra, no futuro, um botão dentro
do próprio SaaS chamar a extensão direto (ex.: "Conectar TikTok" clicado
*dentro* do RAgentes, sem precisar abrir o popup manualmente) — **sem que
esta spec construa esse lado agora**. Nesta fase:
- O manifest ganha o campo, com os 2 domínios.
- O `background/` da extensão ganha um listener mínimo
  (`chrome.runtime.onMessageExternal.addListener`) que por enquanto só
  responde a um `ping` (`{ok: true, version}`) — prova que o canal
  funciona, sem nenhuma ação real disparada por ele ainda.
- **Nenhum código novo entra no `agent-platform/frontend` nesta spec** — o
  dono foi explícito: "não vamos mexer no RAgent por enquanto". O botão que
  chamaria isso de dentro do SaaS fica pra quando a spec de integração
  (seção 6c/12) for escrita.

### 7c. Registry de providers (`providers.ts`)

```ts
interface UnofficialProvider {
  id: 'instagram_web' | 'facebook_web' | 'tiktok_web'
  nome: string
  loginUrl: string
  cookieDomain: string
  cookieDeSessao: string[]   // nomes de cookie que indicam login concluído
  extrairExternalLabel?: (cookies: chrome.cookies.Cookie[]) => string | null
}

export const PROVIDERS: UnofficialProvider[] = [
  {
    id: 'instagram_web',
    nome: 'Instagram',
    loginUrl: 'https://www.instagram.com/accounts/login/',
    cookieDomain: 'instagram.com',
    cookieDeSessao: ['sessionid'],
  },
  {
    id: 'facebook_web',
    nome: 'Facebook',
    loginUrl: 'https://www.facebook.com/login',
    cookieDomain: 'facebook.com',
    cookieDeSessao: ['c_user', 'xs'],
  },
  {
    id: 'tiktok_web',
    nome: 'TikTok',
    loginUrl: 'https://www.tiktok.com/login',
    cookieDomain: 'tiktok.com',
    cookieDeSessao: ['sessionid', 'sid_tt'],
  },
]
```

Os nomes exatos de cookie (`sessionid`, `c_user`/`xs`, `sid_tt`) precisam
ser **confirmados contra sessão real** no início da implementação (inspecionar
DevTools → Application → Cookies numa sessão logada de teste) — os valores
acima são o que é publicamente documentado como estável hoje, mas cada
provider pode ter mudado; primeira tarefa de implementação, não assumir.

### 7d. Bundle de cookies — o que exatamente vai no POST

**Não manda todos os cookies do domínio.** Só os que estão em
`cookieDeSessao` da seção 7c, mais quaisquer outros que a validação
empírica (7c, "confirmar contra sessão real") mostrar como necessários pra
reconstruir a sessão depois. Reduz superfície de exposição — segue o
princípio de mínimo necessário do documento original (seção 9).

### 7e. Login da extensão (popup inicial)

Tela simples: campo email, campo senha, botão "Entrar" — chama
`POST /api/auth/login` do `agent-platform`. Em caso de sucesso, guarda
`{token, chatwoot_sso_url, public_base_url, tenant_name}` em
`chrome.storage.local` e mostra o menu principal (seção 3). Erro de
credencial mostra a mesma mensagem que o login web já usa.

## 8. Claude/Codex — por que ficam de fora do v1 (mas aparecem na lista)

O dono pediu que apareçam no menu "Logins não oficiais" junto com
Instagram/Facebook/TikTok. **Tecnicamente não são o mesmo mecanismo**:

- Instagram/Facebook/TikTok: a credencial que precisamos **é** a sessão do
  navegador (cookie) — é literalmente como esses "canais não oficiais" já
  funcionam hoje (produto-05 §4g).
- Claude/Codex: o que o sistema precisa é um **access_token/refresh_token
  OAuth** obtido via um code exchange PKCE contra um `redirect_uri` fixo
  (`console.anthropic.com`/`localhost:1455`) — não é a sessão web do
  `claude.ai`/`chatgpt.com`. Capturar o cookie da sessão web **não
  substitui** esse token; são credenciais de natureza diferente (produto-08
  §1).

Por isso, nesta spec, Claude/Codex aparecem na lista **desabilitados**
("em breve") — a UI já reserva o espaço (o dono quer os 5 ali desde já),
mas nenhum adapter é implementado pra eles. Se a POC dos 3 primeiros
provider funcionar bem, um adapter futuro pra Claude/Codex via extensão
precisaria interceptar o *code* do redirect OAuth (não o cookie) — desenho
separado, fora do escopo aqui.

## 9. Empacotamento e distribuição — sem Chrome Web Store por enquanto — CONCLUÍDO E TESTADO

Card de download implementado em `agent-platform/frontend/src/pages/Dashboard.tsx`
(commit `2831ce3`), zip em `frontend/public/ratende-connector.zip` (Vite
copia pra `dist/` na raiz, servido pelo mesmo `_mount_spa` que já serve o
resto do frontend — decisão da seção original, opção "backend", não GCS).
**Testado de verdade**: Playwright (`ratende-connector-download.spec.ts`)
loga como usuário de tenant real (não master), confirma que o card
aparece, o link tem o `href` certo, e `GET /ratende-connector.zip` responde
`200` com assinatura de arquivo ZIP válida (`PK`) e tamanho >1KB (não é
página de erro disfarçada de sucesso). 1/1 passando.

**Ponto em aberto, registrado no commit**: o zip precisa ser regenerado
manualmente (`npm run build` no repo `ratende-connector` + zip + copiar
pra `agent-platform/frontend/public/`) toda vez que a extensão mudar —
não tem CI automático fazendo isso ainda. Aceitável pra esta fase de POC,
mas listar como TODO se a extensão for adiante de verdade.

Store pública fica de fora por ora (processo de review próprio, incerto,
não é o foco da POC). Distribuição via **"carregar sem compactação"** (modo
desenvolvedor do Chrome):

1. `npm run build` gera `dist/` já no formato de extensão descompactada.
2. Pipeline (ou manual, nesta primeira fase) zipa `dist/` →
   `ratende-connector.zip`.
3. **Link de download no Início (Dashboard) do RAgentes, não na tela de
   login** — pedido explícito do dono. Card novo em `pages/Dashboard.tsx`
   (mesmo padrão visual dos cards já existentes ali), só visível pra quem
   já está autenticado, com:
   - Botão "Baixar RAtende Connector" → baixa o zip.
   - Instruções curtas: "Extraia o arquivo, abra `chrome://extensions`,
     ative o Modo desenvolvedor, clique em 'Carregar sem compactação' e
     selecione a pasta extraída."
4. O zip fica hospedado como asset estático servido pelo próprio backend
   (mesmo mecanismo que já serve o build do frontend) ou um bucket GCS
   público de baixo custo — decisão de implementação, não bloqueia o
   desenho.

## 10. Segurança e privacidade — o que já está coberto, o que fica pra depois

Cobertos por decisão explícita do dono (seção 2): nível de proteção do
token da extensão = mesmo da sessão web normal, sem cofre adicional.

Ainda assim, não negociável (mesma régua do documento original, seções
11/12):
- Cookies **nunca** em log (extensão nem backend) — sanitizar
  `cookie`/`session`/`authorization`/`token` de qualquer log.
- Cookies cifrados em repouso (`crypto.py:encrypt`, já em uso).
- `chrome.storage.local`, nunca `.sync`.
- Consentimento explícito antes de enviar (clique manual, nunca captura
  automática em background — seção 5, passo 6).
- `_serialize()` nunca devolve o valor cifrado pro frontend/extensão de
  volta.

## 11. Critérios de aceite desta POC

1. Extensão builda (`npm run build`), carrega sem compactação no Chrome sem
   erro no `chrome://extensions`.
2. Login da extensão contra o `agent-platform` local/homolog funciona;
   token persiste entre aberturas do popup.
3. "Abrir RAtende" e "Abrir RAgentes" abrem as URLs certas em nova aba.
4. Fluxo de captura testado de ponta a ponta com **pelo menos o TikTok**
   (provider de prova, o que mais importa): login manual numa conta de
   teste real, extensão detecta sessão, usuário confirma, `POST
   /api/unofficial-connections` chega no backend, linha aparece no
   Postgres com `cookies_encrypted` preenchido (nunca em texto puro — checar
   direto no banco), listagem no popup mostra a conta conectada.
5. Remover uma conta funciona (`is_active=false`, some da lista).
6. **Nada em `oauth-browser`, no fluxo VNC, ou nas rotas/tabelas de
   Claude/Codex foi alterado** — checar `git diff` restrito às pastas novas
   + `backend/migrations`/`backend/app/routes/unofficial_connections.py`/
   `permissions.py`.
7. Teste de isolamento: conta capturada pelo tenant A nunca aparece na
   listagem do tenant B (mesmo padrão de prova já usado em
   `email-accounts`/`google-accounts`, adaptar `credenciais.spec.ts` ou
   criar `unofficial-connections.spec.ts` análogo).
8. `externally_connectable` funciona no nível de canal: a partir do console
   do DevTools numa aba aberta em `ia.rangeltech.net` ou
   `chat.rangeltech.net`, `chrome.runtime.sendMessage(EXTENSION_ID, {type:
   "ping"})` recebe `{ok: true, version}` de volta. Uma aba de um domínio
   **fora** da lista (ex. `example.com`) não consegue mandar mensagem
   nenhuma (erro de canal, comportamento padrão do Chrome pra domínio não
   autorizado) — confirma que o `matches` está restringindo de verdade, não
   é só decoração no manifest.

## 12. Fora de escopo (explícito)

- Qualquer wiring com `chatwoot-rt` (combobox de qual credencial usar por
  canal, criação de inbox a partir da credencial capturada).
- Usar de fato os cookies capturados pra ler/mandar mensagem — só a
  captura e o armazenamento são provados aqui.
- Revalidação periódica automática da sessão (`status`/`last_validated_at`
  existem no schema, sem consumidor nesta spec).
- Adapter de Claude/Codex (seção 8).
- Publicação na Chrome Web Store.
- Firefox/outros navegadores — só Chrome/Chromium (Manifest V3) nesta POC.
