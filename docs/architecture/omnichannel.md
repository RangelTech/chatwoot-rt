# Arquitetura omnichannel

## Quem é dono do quê

| Domínio | Dono | Por quê |
|---|---|---|
| Identidade, tenants, templates, kernel de IA | `agent-platform` | Continua sendo o sistema mestre; nada disso é replicado aqui. |
| Conversas, filas, times, notas privadas, UX do atendente | Chatwoot | É o produto pronto para operação humana. |
| Mapeamento entre os dois, canais, idempotência, handoff | ponte (`bridge/`) | É onde mora a diferenciação — e o que não cabe em nenhum dos dois. |

## Caminho de uma mensagem

```
cliente no WhatsApp
      │
      ▼
W-API ──webhook──▶ bridge  POST /webhooks/wapi/{token}
                     │  1. resolve o tenant pela URL
                     │  2. grava o corpo cru
                     │  3. deduplica pelo id do provedor
                     ▼
                  Chatwoot (inbox de API): contato, conversa, mensagem
                     │
                     ▼
             Agent Bot ──▶ bridge POST /agent-bot
                     │        │
                     │        ▼
                     │   agent-platform POST /v1/messages (kernel)
                     │        │
                     │        ├── resposta ──▶ Chatwoot ──▶ bridge /outbound ──▶ W-API ──▶ cliente
                     │        └── [[HANDOFF]] ─▶ nota privada + fila do time
                     ▼
                atendente humano assume (a IA se cala)
```

## Máquina de estados da conversa

```
ai_active ──resposta da IA──▶ ai_active
    │
    ├── IA pede handoff ─────▶ human_queue ──▶ human_active ──▶ resolved
    ├── kernel indisponível ─▶ human_queue  (com nota explicando)
    └── humano escreve ──────▶ human_active
```

A regra que evita o pior defeito desta arquitetura — IA e atendente
respondendo ao mesmo tempo — é uma só: **o bot só fala em `ai_active`**.
Quando um usuário do Chatwoot manda mensagem pública, a ponte marca
`human_active` no mesmo evento, antes de qualquer processamento de IA.

## Estados de exceção

| Estado | Quando | O que acontece |
|---|---|---|
| `duplicate_ignored` | provedor reenvia o mesmo evento | índice único barra; nada é duplicado |
| `unknown_channel` | webhook em token inexistente | registrado sem tenant; nunca cai em conta alheia |
| `unparseable` | corpo não é JSON | 200 + corpo cru gravado, sem retry infinito |
| `no_content` | status/ack/eco | ignorado |
| `retry_scheduled` | Chatwoot fora do ar | evento fica pendente com o motivo |
| `provider_unavailable` | W-API fora do ar na saída | resposta gerada, entrega pendente |
| `dead_letter` | erro definitivo | exige intervenção; corpo cru preservado |

## Isolamento por tenant

1. **A âncora é `tenant_id`** do agent-platform; toda tabela da ponte pendura nela.
2. **O tenant é resolvido antes do corpo**: o webhook usa um token opaco na URL,
   então uma mensagem forjada não escolhe em qual conta vai cair.
3. **Um canal pertence a um tenant só**: tentar registrar o mesmo
   `(provider, external_id)` em outro tenant é rejeitado.
4. **Credenciais são cifradas** (Fernet) e nunca voltam pela API.
5. **Uma Account do Chatwoot por tenant**, ligada por `tenant.chatwoot_account_id`.

## Compute e estado

- Cloud Run: `chatwoot-web`, `chatwoot-worker` (Sidekiq, `min-instances=1`) e
  `chatwoot-bridge`.
- VPS: PostgreSQL (`chatwoot_prod` e `chatwoot_bridge`), Redis dedicado com TLS
  e MinIO para anexos.
- Nada de estado no Cloud Run: instância pode morrer a qualquer momento.
