# Inventario do rebrand LUAR (kit U6)

Escopo desta entrega: kit de marca e textos visiveis de produto que independem de deploy. Spec: 09B §2.2 e §2.3.
A troca efetiva em producao so acontece em U6, com `rails rt:brand:snapshot` antes e `rails rt:brand:apply` depois.

## Arquivos alterados

| Arquivo | Superficie | Antes | Depois | Status |
|---|---|---|---|---|
| `public/brand-assets/logo.svg` | Logo horizontal claro (login, sidebar, e-mail) | logo Woot/RAtende | lua `#75C8F2` + wordmark LUAR `#0A1733` em paths, viewBox 352x150, protecao 25 (0,25x o diametro) | feito |
| `public/brand-assets/logo_dark.svg` | Logo horizontal escuro | idem | mesma lua, wordmark `#FFFFFF`; recorte e vazado por geometria (evenodd), transparente de verdade | feito |
| `public/brand-assets/logo_thumbnail.svg` | Miniatura, favicon 512, sidebar | disco Woot | so a lua, viewBox 100x100 | feito |
| `public/favicon-{16,32,96,512}.png`, `android-icon-*`, `apple-icon-*`, `apple-icon*.png`, `ms-icon-*` | Favicon, Android/PWA, iOS, tiles | arte Chatwoot | lua rasterizada do SVG (librsvg); favicon/android transparentes, apple/ms sobre branco com respiro | feito (so tamanhos ja referenciados) |
| `public/favicon-badge-{16,32,96}.png` | Favicon com aviso de notificacao (`faviconHelper.js`) | disco + ponto vermelho | lua + ponto vermelho `#FF3B30` com anel vazado | feito |
| `public/manifest.json` | PWA | name/short_name Chatwoot; cores `#2781F6` | `LUAR`; theme `#0A1733`, background `#FFFFFF` | feito |
| `public/browserconfig.xml` | Tile Windows | TileColor `#ffffff` | `#0A1733` | feito |
| `config/installation_config.yml` | Valor padrao de instalacao | `INSTALLATION_NAME`, `BRAND_NAME` = RAtende | `LUAR`; `LOGO*` ja apontavam para `/brand-assets` | feito (YAML so vale em instalacao nova) |
| `lib/tasks/rt_brand.rake` | Valor efetivo no banco | n/a | `rt:brand:apply` (idempotente, limpa `GlobalConfig`) e `rt:brand:snapshot` (JSON para rollback) | feito, com spec |
| `app/views/layouts/vueapp.html.erb` | Meta, tile, theme-color | `#2781F6`; descricao generica de atendimento Chatwoot | `#0A1733`; descricao factual LUAR | feito |
| `app/views/installation/onboarding/index.html.erb` | Onboarding | title/alt/saudacao Chatwoot | `SuperAdmin \| LUAR`, alt `Luar`, "Howdy, Welcome to LUAR" | feito |
| `app/views/super_admin/devise/sessions/new.html.erb` | Login Super Admin | title/alt Chatwoot | `SuperAdmin \| LUAR`, alt `Luar` | feito |
| `app/views/super_admin/application/_navigation.html.erb` | Navegacao Super Admin | alt `Chatwoot Admin Dashboard` | alt `Luar Admin`; linha de versao do motor mantida | feito |
| `app/javascript/dashboard/components-next/icon/Logo.vue` | Fallback do logo (sidebar, switcher) | SVG Woot embutido | lua LUAR embutida; `alt="Luar"` na imagem | feito, compilado com `@vue/compiler-sfc` |
| `app/javascript/survey/views/Response.vue` | CSAT anonimo | alt `Chatwoot logo` | alt `Luar logo` | feito |
| i18n `en`/`pt_BR` `login.json` (TITLE) | Login | Login to / Entrar no Chatwoot | LUAR | feito |
| i18n `en`/`pt_BR` `signup.json` (GET_STARTED) | Cadastro | Chatwoot | LUAR | feito |
| i18n `en`/`pt_BR` `resetPassword.json` (DESCRIPTION; ERROR_MESSAGE pt_BR) | Recuperacao de senha | Chatwoot | LUAR | feito |
| i18n `en`/`pt_BR` `settings.json` (aparencia; NO_ACCOUNT_WARNING en) | Configuracoes | Chatwoot | LUAR | feito |

## Pendente (fora deste kit)

| Item | Motivo |
|---|---|
| `BRAND_URL`, `WIDGET_BRAND_URL`, `TERMS_URL`, `PRIVACY_URL` | Dependem de pagina LUAR real (dominio/DNS/TLS ainda nao existem). `rt:brand:apply` nao os altera. |
| `signup.json` TERMS_ACCEPT (links chatwoot.com) | O formulario troca por URLs globais; so revisar quando as URLs legais LUAR existirem. |
| `legal/*.html.erb`, mailers, `base.liquid`, `enterprise/.../confirmation_instructions`, MFA issuer, push, `Branding.vue`, widget i18n e demais idiomas, links de ajuda/changelog, empty state de campanhas, preview do widget, avatar do bot | Escopo das demais etapas de U6 (§2.3 C/D); exigem revisao editorial/juridica ou dominio. |
| `public/apple-touch-icon.png`, `apple-touch-icon-precomposed.png` | Arquivos vazios (0 bytes) no upstream; nao referenciados, nao gerados. |
| Versao monocromatica, fonte vetorial editavel e teste a 16/24/32 px em tela real | Entregar na revisao de design; PNG 16/32 gerados e conferidos visualmente. |
| Licenca da fonte do wordmark | Nao se aplica: o wordmark e geometria propria (paths), sem fonte embutida. |

## Preservado por ser tecnico ou licenca

| Item | Motivo |
|---|---|
| `window.chatwootConfig`, `window.$chatwoot`, `window.chatwootSDK`, `window.chatwootSettings` | Contrato publico do SDK/widget |
| Eventos `chatwoot:*`, `chatwoot-widget:`, cabecalhos `X-Chatwoot-*` | Contrato de integracao |
| Pacotes `@chatwoot/*`, nomes de tabela/classe/feature flag, rotas e webhooks antigos | Compatibilidade; renomear exige migracao propria |
| `ragentes_branding` (`App.vue`) | Dado de compatibilidade das Accounts |
| `v3/views/auth/signup/Index.vue` (`installationName === 'Chatwoot'`) | Predicado tecnico: com LUAR a instalacao deixa de ser tratada como a do upstream, que e o comportamento desejado |
| SAML tooltip "Unique identifier for Chatwoot as the Service Provider" (`settings.json`) | Identificador funcional do SP; nao trocar antes de migracao |
| `LICENSE`, copyrights, `enterprise/`, `disable_branding`, `IS_ENTERPRISE` | Licenca e creditos obrigatorios |
| `Chatwoot.config[:version]` no Super Admin | Versao do motor, area tecnica |
| Nome/logo de Account, inbox, portal, conversas | Dado de cliente, fora do rebrand global |
