# CH-0b: adaptador Matrix -> Chatwoot (decisao: adaptador proprio no gateway)

Data: 20/10/2026. Referencia lida: `beeper/chatwoot` (Go, Apache-2.0, ~2,3 mil linhas, ultimo commit 07/01/2026).

## O que o `beeper/chatwoot` e de fato
- Um **bot unico**: loga como UM usuario Matrix (`@help:`) e espelha as DMs recebidas por ele para
  UMA caixa (`chatwoot_account_id` e `chatwoot_inbox_id` fixos no `example-config.yaml`).
- Mapeia sala <-> conversa em `chatwoot_conversation_to_matrix_room`; trata texto, anexos,
  edicao/reacao como texto e redacao; rotulo `canonical-dm`.
- Nao ha conceito de tenant, de varias caixas por conexao, de estado de login, de idempotencia
  por id externo nem de webhook assinado.

## Decisao
**(B) adaptador proprio**, como a spec recomendava. Motivos medidos na leitura do codigo:
1. Multi-tenant e "1 caixa por conexao" exigem trocar a configuracao global por mapeamento
   por conexao em todo o fluxo (`chatwoot.go`, `matrix-handler.go`, banco): equivale a reescrever.
2. Escrita em Go + banco proprio (pgx) fora da nossa pilha Python/Postgres; manter fork parado ha 9 meses.
3. Precisamos de: usuario Matrix por conexao (`@luar_t<conta>_c<id>`), estados, outbox/dead-letter,
   auditoria sem segredos, webhook assinado para o Rails (Chatwoot continua dono das conversas).

## O que foi reaproveitado como ideia (Apache-2.0)
- Tabela de mapeamento sala -> conversa (aqui `rt_channel_rooms`, ja com `connection_id`/`account_id`).
- Tratar edicao/reacao como texto quando o Chatwoot nao suporta; ignorar notas privadas na saida.
- Erros de ponte como mensagem privada (futuro, CH-8).

## Como ficou
`bridge/app/channels/appservice.py`: aplicacao Matrix (appservice) recebe `PUT /_matrix/app/v1/transactions/{txn}`,
idempotente por `txn_id` e por `event_id`; sala sem mapeamento ou de outra conexao e ignorada;
saida: `MatrixSender` envia como o usuario Luar da conexao (`?user_id=`) com o `as_token`.
Gateway (`service.py`) entrega ao Rails por webhook assinado (HMAC, janela de 300 s).
Pendente de conta real (teste conjunto): criacao automatica de portais/salas pelo bridge e
vinculo `rt_channel_rooms` a partir do evento de criacao de sala (hoje coberto por fixture).
