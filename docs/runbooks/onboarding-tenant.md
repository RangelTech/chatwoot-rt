# Runbook — colocar uma empresa para atender

Ordem obrigatória. Cada passo é idempotente: repetir não duplica nada.

## 1. Provisionar a operação (pela plataforma)

Na tela **Atendimento** do agent-platform, clique em *Criar operação de
atendimento*. Isso chama a ponte e:

- cria a `Account` no Chatwoot;
- grava `tenant.chatwoot_account_id`;
- espelha o usuário logado como **administrador** daquela conta.

O administrador não é detalhe: é o usuário cujo token a ponte usa depois para
criar inbox e operar a Application API.

## 2. Entrar no atendimento

Ainda na tela **Atendimento**, *Abrir atendimento* gera um link temporário de
login (Platform API). Ninguém digita senha nova e ninguém se recadastra.

## 3. Ligar o canal de WhatsApp

```bash
curl -X POST "$BRIDGE_URL/admin/channels" \
  -H "Authorization: Bearer $BRIDGE_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"tenant_id":"<uuid do tenant>","provider":"wapi",
       "external_id":"<instance id da W-API>","token":"<token da instância>"}'
```

A resposta traz `webhook_path`. Cadastre `"$BRIDGE_URL$webhook_path"` como
webhook da instância no painel da W-API.

Valide a credencial **sem mandar mensagem para ninguém**:

```bash
curl -X POST "$BRIDGE_URL/admin/channels/<channel_id>/test" \
  -H "Authorization: Bearer $BRIDGE_ADMIN_TOKEN"
```

## 4. Apontar qual agente atende

```bash
curl -X POST "$BRIDGE_URL/admin/ai-config" \
  -H "Authorization: Bearer $BRIDGE_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"tenant_id":"<uuid>","chatwoot_inbox_id":<id>,
       "template_id":"<uuid do template>",
       "integration_key":"<api key de integração do agent-platform>",
       "autopilot":true,"handoff_team_id":<id do time>}'
```

A `integration_key` sai de **Integrações** no agent-platform (canal `api`). É
ela que dá ao agente o template, o modelo e as tools certas.

## 5. Ligar o Agent Bot no Chatwoot

No Chatwoot (super admin), crie um Agent Bot apontando para
`"$BRIDGE_URL/agent-bot"` e associe-o à inbox do tenant.

## Como desligar a IA sem derrubar o atendimento

`autopilot: false` em `/admin/ai-config`. As conversas continuam chegando e os
humanos seguem atendendo; só o bot para de responder.

## Quando algo não chega

1. `channel_events` no banco da ponte tem o corpo cru e o estado de cada evento.
2. `state = 'retry_scheduled'` → Chatwoot estava fora; reenviar pelo provedor.
3. `state = 'provider_unavailable'` → a resposta existe, a entrega falhou.
4. `state = 'dead_letter'` → precisa de intervenção; o motivo está em `detail`.
