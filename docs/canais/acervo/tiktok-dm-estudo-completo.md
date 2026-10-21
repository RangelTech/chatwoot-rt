<!-- Copia redigida (cookies, tokens, senhas e hashes longos removidos) de: C:/Users/lucas.rangel/Desktop/<acervo-pessoal>/personal-skills/mega-spec-reestrutura/concluidas/tiktok-dm-estudo-completo.md -->
> **28/08/2026 — arquivo movido pra `concluidas/`, condensado nas 3 specs vivas da mega-spec.** Conteúdo absorvido em `../estudo-01-pesquisa-e-bloqueios-externos.md`.

# TikTok DM — estudo completo (ler e mandar mensagem via cookie, sem Playwright)

> Pedido do dono, 27/08/2026: "descubra como ler mensagens da DM e como
> enviar mensagens na DM, tudo extremamente catalogado". Este documento
> é o resultado real dessa investigação — o que foi **confirmado ao
> vivo** (com o cookie real capturado pela extensão), o que é
> **conhecimento de mercado sem confirmação própria**, e o que
> **genuinamente não dá pra descobrir sem 1 captura de rede real do
> dono** (explicado por quê, com passo a passo exato no final).

## 1. O que foi CONFIRMADO ao vivo (27/08/2026, madrugada)

### 1.1 A sessão capturada pela extensão autentica de verdade, sem Playwright

```
GET https://www.tiktok.com/passport/web/account/info/
Cookie: <jar completo, 54 cookies, capturado por produto-15>
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ...
Referer: https://www.tiktok.com/
```

Resposta real, HTTP 200:

```json
{"data":{"user_id":6959968446961239046,"user_id_str":"6959968446961239046",
"sec_user_id":"[REDIGIDO-LONGO]",
"screen_name":"Lucas Rangel770","username":"lucasrangel770","email":"l***[EMAIL-REDIGIDO]",
"connects":[{"screen_name":"Lucas Rangel","platform":"google", ...}], ...},
"message":"success"}
```

**Isso muda a conclusão anterior** (`produto-05` §4g dizia "TikTok
confirmado inviável") — aquela conclusão era só sobre **automação de
navegador (Playwright) travando o processo**, nunca tinha testado
cookie+HTTP direto isolado. Agora está confirmado: **dá pra autenticar
sem navegador nenhum**, só com o cookie que a extensão já captura.

**Dado novo e valioso**: a resposta trouxe o `sec_user_id`
(`MS4wLjABAAAAd2W6...`) — é o identificador interno do TikTok que a
maioria dos endpoints privados (incluindo, provavelmente, os de DM)
exige. Não é o mesmo que `user_id` numérico — é um formato próprio
(base64-like, prefixo `MS4w`), só se consegue via uma chamada
autenticada como esta.

### 1.2 Nem todo endpoint exige assinatura (`X-Bogus`) — mas os endpoints "de valor" provavelmente exigem

O teste acima funcionou **sem** nenhum parâmetro de assinatura
(`X-Bogus`/`X-Gnarly`/`msToken`/`x-tt-params`) — só cookie + User-Agent
+ Referer. Isso confirma que **pelo menos alguns** endpoints do
TikTok Web aceitam chamada simples. Mas é esperado que endpoints mais
sensíveis (mensagens, ações de escrita) exijam a assinatura completa —
ver seção 3.

### 1.3 5 tentativas de adivinhar o endpoint de mensagens — todas "url doesn't match" (sessão válida, caminho errado)

| URL tentada | Resposta |
|---|---|
| `/api/v1/message/get_conversation_list/?aid=1988` | `200 {"status_msg":"url doesn't match"}` |
| `/api/message/get_history/?aid=1988` | `200 {"status_msg":"url doesn't match"}` |
| `/api/im/v1/conversation/list/?aid=1988` | `200 {"status_msg":"url doesn't match"}` |
| `/tiktok/v1/message/get_stranger_list/?aid=1988` | devolveu HTML (página normal, não API) |
| `/api/v1/im/conversation/list?aid=1988&device_platform=web` | `200 {"status_msg":"url doesn't match"}` |

**Importante**: nenhuma dessas tentativas devolveu erro de sessão ou
permissão — sempre "url doesn't match", que é o TikTok dizendo "essa
rota não existe assim", não "você não tem acesso". A sessão continua
100% válida em todas. Isso é **sinal positivo** (a infraestrutura de
auth funciona), só falta achar o caminho certo.

## 2. Pesquisa de mercado (repetida desta madrugada, sem novidade real)

### 2.1 Bibliotecas open-source — nenhuma serve pra DM via cookie+HTTP direto

| Projeto | Status | Serve pra DM? |
|---|---|---|
| `davidteather/TikTok-Api` | Ativo, popular | Não — o próprio README diz que não tem rotas autenticadas |
| `armxe/tiktok-api` | Ativo, 310 estrelas | Não — só a camada de assinatura (`X-Bogus`/`X-Argus`/`X-Gorgon`), sem login/sessão/DM. **Mas é o mais útil dos quatro** — se acharmos o endpoint certo e ele precisar de assinatura, esse projeto já tem a implementação Python de `X-Bogus` pronta, reaproveitável. |
| `szdc/tiktok-api` | Arquivado 2021 | DM foi pedida e recusada como "wontfix" |
| `11AnJo/tiktok_dm` | Baixa atividade | "Sim" no nome, mas usa **Selenium** (navegador automatizado) — mesma categoria de risco que já falhou pro TikTok (produto-05 §4g) |
| `justbeluga/tiktok-web-reverse-engineering` | Documenta `X-Bogus`/`X-Gnarly` do lado web | Não documenta nenhum endpoint de mensagem |

### 2.2 Serviços comerciais — resolvem, mas não publicam como

- **UnifyPort** (`unifyport.ai`, já documentado em `lab-01`): tem produto
  de DM do TikTok funcionando (usam um "Exporter", extensão própria pra
  capturar sessão). Artigo deles ("TikTok DM API: Why There Is No
  Official Endpoint and How Teams Receive Messages Anyway") **não
  revela o mecanismo técnico** — só diz que conectam "como o app faz,
  através de uma conta normal", sem dizer se é cookie+HTTP ou
  automação de navegador por trás.
- **TikAPI** (`tikapi.io`) — achado novo nesta pesquisa, plataforma
  paga similar. Documentação pública também não detalha o mecanismo
  nem confirma suporte a DM especificamente (página truncada na
  consulta, precisaria de conta paga pra ver a doc completa).

**Conclusão**: os dois concorrentes comerciais já resolveram isso, mas
tratam como segredo comercial — não tem atalho público pra copiar.

## 3. Por que não dá pra simplesmente adivinhar o resto (explicação técnica)

O TikTok Web usa um sistema de assinatura de requisição
(`X-Bogus`/`X-Gnarly`/`x-tt-params`) calculado **no navegador, via
JavaScript ofuscado** (uma VM própria deles, difícil de replicar sem
rodar o JS de verdade). Confirmado por pesquisa: `armxe/tiktok-api` e
outros projetos de engenharia reversa dedicam repositórios inteiros só
a isso. **Não é algo que dá pra advinhar por tentativa e erro** — ou
se sabe o algoritmo exato (replicado por engenharia reversa séria,
tipo `armxe`), ou se roda um navegador de verdade que já calcula isso
sozinho (a abordagem que já falhou aqui, Playwright).

A **boa notícia**: nossa sessão real (seção 1.1) já provou que **nem
tudo** exige essa assinatura — `/passport/web/account/info/` funcionou
sem nada disso. É bem possível que **ler** a lista de conversas também
não exija (endpoints de leitura tendem a ser menos protegidos que
endpoints de escrita/ação) — só não sabemos ainda porque não achamos o
caminho certo.

## 4. Próximo passo real — só o dono consegue fazer isso (não automatizável)

**Não dá pra descobrir o endpoint certo sem ver a requisição real que o
próprio navegador do TikTok manda.** Passo a passo exato:

1. Abrir `https://www.tiktok.com/messages` no Chrome (já logado).
2. Abrir o DevTools (F12) → aba **Network**.
3. Filtrar por `Fetch/XHR` (esconde imagem/CSS/etc, deixa só chamada de API).
4. Clicar numa conversa existente (ou abrir uma nova).
5. Procurar na lista de requisições uma que pareça "conversation"/"message"/"chat"/"inbox" no nome.
6. Clicar nela → botão direito → **Copy → Copy as cURL**.
7. Colar esse cURL completo aqui na próxima conversa.

Com isso em mãos, dá pra:
- Confirmar a URL exata (sem precisar advinhar mais).
- Ver se tem `X-Bogus`/`X-Gnarly`/`x-tt-params` no request (se tiver,
  sabe que precisa da camada de assinatura do `armxe/tiktok-api`; se
  não tiver, é chamada simples igual a que já confirmamos funcionando).
- Testar a mesma chamada com o cookie que já temos salvo, confirmando
  se funciona de verdade.

**Pra mandar mensagem** (não só ler), o mesmo processo serve — mandar
uma mensagem de teste pra si mesmo (ou pra uma conta de teste) e copiar
o cURL do request de envio.

## 5. Resumo executivo

| Pergunta | Resposta |
|---|---|
| A sessão da extensão funciona sem Playwright? | ✅ **Sim, confirmado ao vivo** — autenticação real, dado real de conta retornado. |
| Dá pra ler a lista de conversas hoje? | 🟡 **Provavelmente sim, mas o endpoint exato não foi encontrado** — 5 tentativas de adivinhar erraram o caminho (sessão sempre válida, só a URL errada). |
| Dá pra mandar mensagem hoje? | 🟡 Mesma situação — mecanismo deve ser parecido (cookie + talvez assinatura), endpoint exato desconhecido. |
| Precisa de assinatura (`X-Bogus`) pra tudo? | ❌ **Não pra tudo** — `/passport/web/account/info/` funcionou sem. Desconhecido se mensagens precisam. |
| Alguma lib open-source resolve isso pronto? | ❌ Não — nenhuma madura documenta DM via cookie+HTTP (só `armxe/tiktok-api` tem a peça de assinatura, reaproveitável se precisar). |
| Como fechar a lacuna que falta? | 📋 **1 captura de rede real do dono** (`tiktok.com/messages`, DevTools → Network → Copy as cURL) — não automatizável, é a única coisa que falta. |

## 6. Referências

- [`lab-01-unifyport-tiktok.md`](lab-01-unifyport-tiktok.md) — POC do provider comercial UnifyPort, alternativa se o caminho próprio não fechar.
- [`produto-05-chatwoot-integracao-completa.md`](produto-05-chatwoot-integracao-completa.md) §4g — histórico completo do TikTok Unofficial (Playwright travando, pesquisa de libs anterior).
- `armxe/tiktok-api` — https://github.com/armxe/tiktok-api (implementação real de `X-Bogus`/`X-Argus`/`X-Gorgon`, reaproveitável se o endpoint de DM exigir assinatura).
- UnifyPort, artigo sobre por que não existe API oficial de DM — https://www.unifyport.ai/blog/tiktok-no-dm-api-receive-messages/
- TikAPI (plataforma comercial, não confirmado suporte a DM) — https://tikapi.io/documentation/
