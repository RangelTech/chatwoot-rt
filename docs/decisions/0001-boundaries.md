# Decisões estruturais do repositório

## 1. Chatwoot entra empacotado, não forkado

A imagem oficial é a base; só sobrepomos branding e entrypoints. Atualizar é
trocar `CHATWOOT_VERSION`, não resolver merge de upstream.

**Consequência aceita**: o que não dá para fazer por configuração, asset ou API
não é feito. Se um dia for inevitável tocar o core, isso vira uma decisão nova
registrada aqui, com o custo de manutenção explícito.

## 2. A ponte não repete estado que já existe

A ponte guarda três coisas: mapeamentos entre os dois sistemas, o que garante
entrega única e o estado de quem está no comando da conversa. Contato, mensagem
e histórico ficam no Chatwoot; template, modelo e memória ficam no
agent-platform.

**Por quê**: dado duplicado é dado que diverge.

## 3. Deduplicação no banco, não em memória

O índice único `(provider, dedup_key)` é a garantia. Cloud Run sobe e desce
instâncias; um cache em memória não sobreviveria a isso e a conversa duplicaria
justamente sob carga.

## 4. Webhook sempre responde 200

Provedor que recebe 5xx reenvia — e reenvia de novo. Um erro nosso viraria uma
tempestade de retries. Então validamos, gravamos o corpo cru, e respondemos 200
mesmo quando o evento é descartado. O que falhou fica registrado em
`channel_events` com o motivo.

## 5. O worker sobe um respondedor HTTP mínimo

O Sidekiq não escuta porta nenhuma, e o Cloud Run exige que o container escute
em `$PORT`. Em vez de fingir que o worker é um serviço web, ele sobe um socket
minúsculo em background só para o health check e mantém o Sidekiq em primeiro
plano — se a fila morrer, o container morre e o Cloud Run reinicia.

## 6. Migração é passo explícito de deploy

`rails db:chatwoot_prepare` roda como Cloud Run **job**, nunca no boot do web.
Com `min-instances` maior que 1, duas instâncias migrariam o mesmo banco ao
mesmo tempo.

## 7. TLS com certificado próprio na VPS

Postgres e Redis saem para a internet, então exigem TLS — a alternativa seria
senha em texto claro na rede. O certificado é próprio, então a cadeia não é
verificável publicamente e o Chatwoot roda com
`REDIS_OPENSSL_VERIFY_MODE=none`. O tráfego é cifrado; a verificação de cadeia
é o que fica de fora.

**Trabalho futuro**: emitir certificado real para `db.rangeltech.net` e voltar
a verificar a cadeia.

## 8. PgBouncer fica fora do caminho da plataforma

O pooler roda em `pool_mode = transaction`, que quebra prepared statements do
psycopg e do checkpointer do LangGraph. A plataforma e a ponte falam direto com
o Postgres na porta 5433; o PgBouncer continua servindo o resto.
