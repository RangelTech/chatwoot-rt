<!-- Copia redigida (cookies, tokens, senhas e hashes longos removidos) de: C:/Users/lucas.rangel/Desktop/<acervo-pessoal>/personal-skills/mega-spec-reestrutura/concluidas/lab-02-cookies-connector-vs-canais-unofficial.md -->
> **28/08/2026 — arquivo movido pra `concluidas/`, condensado nas 3 specs vivas da mega-spec.** Parte A (Instagram/Facebook) já foi superada pela decisão real de usar Matrix/mautrix-meta (ver `../correcao-01-execucao-completa.md`). Parte B (TikTok) absorvida em `../estudo-01-pesquisa-e-bloqueios-externos.md`.

# Lab-02 — Cookies do RAtende Connector como fonte pros canais Unofficial já existentes

> **Isto não é uma spec de produto nem um plano de QA.** É um **caderno de
> laboratório** — registro de POCs a rodar *se* forem ativadas, sem
> executar nada agora. Criado 26/08/2026, a pedido do dono, **escopo
> confirmado por ele: só documento, sem executar nada** (nenhuma chamada
> real, nenhum cookie real usado, VPS não tocada nesta rodada).
>
> **Nota de 26/08 (ERRADA, ver correção de 28/08 abaixo)**: ~~o pedido
> original citava testar "Matrix/mautrix" — pesquisei e não existe
> mautrix nem protocolo Matrix em lugar nenhum deste projeto...
> provavelmente é isso que foi referenciado numa transcrição de voz~~.
>
> **CORREÇÃO REAL (28/08/2026)**: o dono confirmou de novo, com
> firmeza, que era isso mesmo que ele tinha pedido — `mautrix-facebook`/
> `mautrix-instagram` (descontinuadas mar/2024, substituídas por
> `mautrix-meta`, ativo) são bridges reais e conhecidas do ecossistema
> Matrix, que autenticam exatamente por cookie. A pesquisa de 26/08 foi
> rasa demais (não pesquisei se as libs existiam de verdade antes de
> descartar) — erro real, não do dono. Spec de correção completa:
> [`produto-18-correcao-extensao-litellm-matrix.md`](produto-18-correcao-extensao-litellm-matrix.md).

## Contexto — dois mecanismos de captura de cookie que já existem, nunca conectados

1. **produto-08 (`oauth-browser`)** — Playwright remoto, sessão automatizada
   dentro de um container na VPS. É quem alimenta hoje
   `social_unofficial_connections`/`channel_instagram_unofficial`/
   `channel_facebook_unofficial` no Chatwoot. **TikTok via este caminho
   está CONFIRMADO INVIÁVEL** (produto-05 §4g): login guiado por Playwright
   derrubou o processo do navegador inteiro 2x, mesmo com as mesmas
   medidas anti-detecção que funcionam pra Instagram/Facebook. Pesquisa de
   bibliotecas de assinatura madura (`armxe/tiktok-api`, `davidteather/TikTok-Api`,
   `11AnJo/tiktok_dm`) não achou alternativa madura — nenhuma tem
   login+DM sem automação de navegador.

2. **produto-15 (`ratende-connector`)** — extensão Chrome real, lê cookies
   do navegador de verdade do usuário via `chrome.cookies` API (sem
   Playwright, sem navegador automatizado nenhum). Já captura Instagram,
   Facebook e TikTok com sucesso (sessão real do dono, testado ao vivo
   26/08/2026), grava em `tenant_unofficial_connections`
   (`agent-platform`), **nunca conectado ao Chatwoot** — hoje é só
   armazenamento, sem consumo (mesmo aviso já registrado no docstring de
   `unofficial_connections.py`: "nenhum consumo real acontece aqui").

**Achado que motiva este lab**: os dois mecanismos guardam o cookie no
mesmo formato — lista de `{name, value, domain, path}` (comparar
`ratende-connector/src/lib/providers.ts`/`CookieIn` em
`unofficial_connections.py` contra `cookies_jar`/`cookies_jar=` em
`Channel::InstagramUnofficial`/`Channel::FacebookUnofficial`,
`[REDIGIDO-LONGO].rb`). Como o
Instagram/Facebook Unofficial já leem esse formato via
`SocialUnofficial::InstagramClient`, a pergunta central deste lab é: **dá
pra usar o cookie capturado pela extensão (produto-15) no lugar do cookie
capturado pelo Playwright (produto-08), sem mudar nada no `Channel::*`
nem no client HTTP que já existe?** Se sim, ganha-se: captura mais barata
(sem container Playwright rodando), mais estável (sem risco do processo
morrer), e potencialmente **destrava TikTok** — porque a causa raiz do
TikTok inviável era especificamente o Playwright travando, não uma
limitação do cookie/API em si.

```
HOJE (só Instagram/Facebook):
  navegador remoto (Playwright, produto-08)
        │ captura cookie de sessão
        ▼
  social_unofficial_connections / channel_instagram_unofficial / channel_facebook_unofficial
        │
        ▼
  SocialUnofficial::InstagramClient / FacebookClient  →  Chatwoot (inbox real)

PROPOSTA A TESTAR (lab):
  extensão Chrome real (produto-15, sem Playwright)
        │ captura cookie de sessão (já funciona p/ IG/FB/TikTok)
        ▼
  tenant_unofficial_connections (agent-platform)  ── ??? ──▶  mesmo Channel::*/mesmo client do Chatwoot
```

## Quando rodar este laboratório

1. Quando o dono autorizar execução real ("bora pra dev" ou equivalente
   pra este lab especificamente) — nenhuma etapa abaixo deve ser
   executada antes disso, incluindo passos que pareçam "só leitura".
2. Faz mais sentido priorizar **depois** que produto-15 for reaberto (foi
   fechado/pausado em 26/08 — "fechamos esse conector por enquanto") e
   **depois** de produto-05 §4g ter o envio de resposta do Instagram
   Unofficial validado ao vivo (ainda pendente conforme a spec).

## Roteiro da POC — Parte A: Instagram/Facebook (baixo risco, caminho já provado nos dois lados)

| # | Passo | Resultado esperado | Resultado real (preencher ao rodar) |
|---|---|---|---|
| 1 | Comparar campo a campo o cookie salvo por `tenant_unofficial_connections` (produto-15, tenant de teste) com o formato que `Channel::InstagramUnofficial#cookies_jar=`/`SocialUnofficial::InstagramClient` espera | Mesmos campos (`name`,`value`,`domain`,`path`), nenhuma transformação extra necessária | ✅ **Confirmado por leitura de código, 26/08** — schema idêntico dos dois lados. **Mas achado real além do schema**: a extensão só salvava os cookies do mínimo de detecção de login (`cookieDeSessao`, ex. só `sessionid`), sem `csrftoken` — que `InstagramClient#csrf_token` exige em toda chamada (`X-CSRFToken`). Facebook Unofficial roda dentro de navegador real (Playwright), precisa do jar inteiro pra não cair em reautenticação. **Corrigido** (`ratende-connector` commit `19c66ba`): agora salva o cookie jar completo do domínio, não só o mínimo. Falta recapturar com o build novo e repetir os passos 2-5 pra confirmar na prática. |
| 2 | Escrever um script isolado (fora de produção, tenant de teste dedicado) que lê o cookie cifrado de `tenant_unofficial_connections`, decifra, grava direto num `Channel::InstagramUnofficial` de teste via `cookies_jar=` | Grava sem erro de validação | |
| 3 | Rodar `PollInstagramUnofficialService`/`InstagramClient` manualmente contra esse canal de teste | Lista de conversas reais retorna, igual já acontece com o cookie via Playwright | |
| 4 | Repetir 1-3 pro Facebook | Mesmo resultado | |
| 5 | Medir se o cookie da extensão dura tanto quanto o do Playwright (mesma sessão do navegador real do usuário — teoricamente mais estável, já que não depende de reautenticação automatizada) | Sessão sobrevive por dias sem cair | |

## Roteiro da POC — Parte B: TikTok (risco maior, nenhum `Channel::` existe ainda pra consumir)

**Diferença importante da Parte A**: não existe hoje nenhum
`Channel::TikTokUnofficial`/client no `chatwoot-rt` — a Parte A reaproveita
código pronto, a Parte B exigiria escrever um client novo (mesmo
princípio de `SocialUnofficial::InstagramClient`, mas fazendo scraping
HTTP direto do TikTok Web com o cookie, sem Playwright). Isso é trabalho
de produto, não só teste — este lab só cobre a fase de **validação de
viabilidade antes de decidir se vale escrever esse client**.

| # | Passo | Resultado esperado | Resultado real (preencher ao rodar) |
|---|---|---|---|
| 1 | Com o cookie TikTok já capturado pela extensão (sessão real, `sessionid`/`sid_tt`/`tt_csrf_token` — conferir nomes exatos capturados, `providers.ts`), montar requisições HTTP diretas (`requests`/`httpx`, headers replicando o navegador real) contra endpoints do TikTok Web (ex.: `GET` de inbox/conversas — descobrir endpoint real via devtools numa sessão de teste, não documentado publicamente) | Alguma resposta autenticada (não 401/redirect pra login) | |
| 2 | Se 1 funcionar: tentar ler ao menos a lista de conversas (não precisa DM completa ainda) | Lista real retorna | |
| 3 | Se 2 funcionar: medir por quantos dias a sessão aguenta sem exigir login de novo | Sessão dura tempo suficiente pra uso real (referência: mesma ordem de grandeza do Instagram/Facebook) | |
| 4 | Registrar aqui, explicitamente, se o TikTok reagiu com qualquer sinal de suspeita (captcha, "verificar é você mesmo", logout forçado) — é o dado que faltava (produto-05 já registra que TikTok tem detecção mais agressiva que Instagram/Facebook, "40+ sinais de dispositivo/comportamento") | Sem sinal de suspeita nos passos 1-3 | |

**Critério de corte**: se o passo 1 já vier 401/bloqueado, ou se qualquer
sinal de suspeita aparecer no passo 4, **não escrever o client TikTok** —
registrar aqui como "confirmado inviável também por este caminho" e
manter a decisão existente (produto-05: TikTok Unofficial travado, sem
nova tentativa até surgir caminho diferente).

## Parte C — Dados extras do navegador pra reduzir risco de "sessão duplicada"

Pergunta do dono: dá pra capturar mais coisa além do cookie (ex. nome do
navegador) pra entregar pro serviço que consome a sessão, deixando menos
óbvio que está sendo usada de outro lugar (na prática: da VPS, não do
Windows/Chrome onde a sessão nasceu)?

**O que é capturável e replicável, hoje, pela extensão** (sem
implementação nova de verdade nenhuma nesta lista — Chrome extension API
já expõe isso):
- **User-Agent real do Chrome do usuário**: trivial, `navigator.userAgent`
  já acessível no content script. Grava e reenvia idêntico nas
  requisições HTTP feitas do lado servidor.
- **Accept-Language / timezone**: trivial, mesma lógica.
- **IP/geolocalização**: não capturável pela extensão (não expõe IP
  público), mas contornável com proxy — precisa ser residencial, no
  mesmo país/região do usuário, pra bater com timezone/idioma.

**O que NÃO é trivial** (achado de pesquisa, ver nota de fonte abaixo):
- **Fingerprint TLS/JA3**: o sinal mais forte de "esta requisição não
  veio de um Chrome real" é a assinatura do handshake TLS, que não passa
  por proxy nem é alterável por User-Agent — precisa de biblioteca de
  "TLS impersonation" (ex. `curl-impersonate`, `utls`) pra sequer tentar
  imitar, e navegadores modernos randomizam extensões TLS por conexão,
  reduzindo a confiabilidade mesmo dessas libs.
- Nenhuma fonte oficial da Meta/TikTok documenta publicamente os sinais
  exatos usados pra flagar sessão duplicada — o que está escrito acima é
  conhecimento de mercado de anti-fraude/scraping, não confirmação
  oficial. Tratar como incerteza real, não garantia.

**Proposta de teste (só quando este lab for ativado)**: comparar 2
variações da Parte A/B — (i) requisição HTTP simples do servidor, sem
nenhum spoofing; (ii) mesma requisição com User-Agent/Accept-
Language/timezone do usuário real replicados. Medir se (ii) reduz sinais
de suspeita comparado a (i). Não dá pra medir taxa de ban de verdade sem
volume real e tempo — registrar aqui como limitação conhecida do teste,
não fingir que uma sessão de teste prova segurança de longo prazo.

## Parte D — REMOVIDA (26/08, correção) — já existe, não é lab

Esta parte perguntava se o token OAuth do Codex capturado pela extensão
serve de credencial pro LiteLLM. **Pergunta já respondida por spec
existente, não precisava de lab novo**: `produto-08` §1 já é exatamente
isso — LiteLLM tem suporte nativo a passthrough de OAuth de assinatura
(Claude/Codex), `tenant_ai_accounts`/`_criar_combo_litellm` já
implementados e testados em produção, risco de Termos de Uso **já foi
aceito pelo dono** na decisão de escolher o LiteLLM (`infra-04`,
20/08/2026) — não era uma decisão em aberto. O que faltava de verdade
era só uma conta OAuth real pra testar round-robin (produto-08 §6,
travado por falta de login automatizável) — a extensão resolve
exatamente essa parte. Todo o plano de execução real (ponte de import +
teste de round-robin) está em `produto-08` §6 agora, não aqui.

## Perguntas que este lab precisa responder antes de qualquer decisão de produto

- [ ] Cookie da extensão (produto-15) é aceito sem transformação pelo `Channel::InstagramUnofficial`/`FacebookUnofficial` já existentes?
- [ ] Sessão capturada pela extensão dura mais/menos que a capturada via Playwright?
- [ ] TikTok via requisição HTTP direta (sem Playwright) autentica, ou já falha no passo 1 da Parte B?
- [ ] Se autenticar: quanto tempo a sessão TikTok aguenta sem cair, e aparece algum sinal de suspeita?
- [ ] User-Agent/timezone replicados fazem diferença observável (mesmo que não quantificável em taxa de ban)?
- [x] ~~Codex CLI tem endpoint compatível com OpenAI que aceite o `access_token` capturado?~~ Não se aplica — LiteLLM já faz passthrough do header direto, não chama nenhum endpoint "compatível OpenAI" próprio (produto-08 §1).
- [x] ~~Usar esse token via LiteLLM em produção multi-tenant é aceitável nos Termos de Uso da OpenAI?~~ Risco já aceito pelo dono desde a escolha do LiteLLM (`infra-04`, 20/08) — reconfirmado 26/08 pra Claude+Codex juntos.

## Se a POC validar: próximo passo (fora deste lab)

- Parte A validada → vira mudança de produto real em produto-15 (ligar
  `criarConexao` a um passo novo que espelha o cookie pro
  `Channel::InstagramUnofficial`/`FacebookUnofficial` do tenant, ou
  substitui de vez o capture via Playwright do produto-08 pros dois
  provedores).
- Parte B validada → abre spec de produto nova (`produto-XX`) pra escrever
  `Channel::TikTokUnofficial`/client HTTP direto — escopo de
  implementação real, não cabe neste lab.
- Parte D (ex-) → ver `produto-08` §6, já é execução real, não mais lab.

## Links de referência (pesquisa 26/08/2026)

- JA3/TLS fingerprinting: https://scrapfly.[REDIGIDO-LONGO]
- User-Agent spoofing, por que sozinho não engana detecção séria: https://stytch.com/blog/user-agent-spoofing/
- `armxe/tiktok-api` (só assinatura de requisição, sem login/DM): https://github.com/armxe/tiktok-api
- `davidteather/TikTok-Api` (sem rotas autenticadas): https://github.com/davidteather/TikTok-Api

**CORREÇÃO (28/08/2026)**: a nota acima estava errada. `mautrix-facebook`/
`mautrix-instagram` são bridges reais (descontinuadas em março/2024,
substituídas por `mautrix-meta`, ativo). O dono confirmou de novo que
era isso mesmo que tinha pedido — a pesquisa de 26/08 foi rasa demais,
não devia ter sido descartada sem checar se as libs existiam de
verdade. Spec completa de correção: `produto-18-correcao-extensao-litellm-matrix.md`.
