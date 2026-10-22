# Paridade Evolution API x mautrix-whatsapp

Lista do que o Evolution faz **hoje** no nosso sistema (lida do codigo em 20/10/2026) e o que o `mautrix-whatsapp` precisa igualar antes de aposentar o Evolution (CH-10). Coluna "Status": **pendente de teste conjunto** = depende de numero de WhatsApp de teste do dono (§0-D); nada foi testado com conta real.

Fontes lidas: `bridge/app/services/evolution.py`, `chatwoot/app/services/evolution/{client,incoming_message_service,send_on_evolution_service}.rb`, `chatwoot/app/jobs/webhooks/evolution_events_job.rb`, `chatwoot/app/models/channel/evolution_api.rb`, `bridge/app/api/admin.py`.

## A. O que o Evolution faz hoje (linha de base)
| # | Capacidade atual | Como e feita hoje | Equivalente no mautrix-whatsapp / gateway | Status |
|---|---|---|---|---|
| 1 | Isolamento por tenant | 3 containers por conexao (Evolution + Redis + Postgres), nome derivado do tenant | 1 processo compartilhado; 1 usuario Matrix por conexao (`@luar_t<conta>_c<id>`) | pendente de teste conjunto (2 contas no mesmo processo sem cruzar) |
| 2 | Conectar por QR | `GET /instance/connect`, QR devolvido ao Luar | `login/start` flow `qr` (renova, contagem regressiva) | pendente de teste conjunto |
| 3 | Conectar por codigo de pareamento | nao usado no Luar hoje | flow `phone` (medido: pede phone_number) | pendente de teste conjunto |
| 4 | Estado da conexao | `connection.update` (webhook) e `connection_state` | estados `connected/degraded/reauth_required/...` + health em 3 niveis | pendente de teste conjunto |
| 5 | Reconexao | `reconnect` (novo QR) | `reauth` no assistente (QR novamente) | pendente de teste conjunto |
| 6 | Texto de entrada | `messages.upsert`; le `conversation` e `extendedTextMessage.text`; ignora `fromMe` duplicado por `source_id` | evento normalizado `message.created`, `source_id = external_id` | pendente de teste conjunto |
| 7 | Texto de saida | `POST message/sendText/{instancia}` (`number`, `text`) | `POST /connections/{id}/send` idempotente (outbox) | pendente de teste conjunto |
| 8 | Status de entrega/leitura | `messages.update`: `DELIVERY_ACK`->delivered, `READ`/`PLAYED`->read | eventos `message.status` / `message_status_events` | pendente de teste conjunto |
| 9 | Deduplicacao | `inbox.messages.exists?(source_id: message_id)` | chave unica `(account_id, connection_id, external_id)` | testado com fixtures (gateway); real pendente |
| 10 | Confiabilidade do webhook | retry 10x, 5 s inicial, timeout 60 s (Evolution -> Rails) | webhook assinado do gateway com *outbox*/dead-letter e replay protegido (Rails -> idempotente) | testado com simulador; real pendente |
| 11 | Identidade de sessao | "Windows/Chrome" no "aparelho conectado" | configuravel no bridge (nome do dispositivo); conferir | pendente de teste conjunto |
| 12 | Armazenamento minimo | nao salva mensagens/contatos/chats no Evolution (`DATABASE_SAVE_DATA_*=false`) | Matrix guarda copia transitoria; retencao em `RETENCAO_E_CONSENTIMENTO.md` | decisao documentada |
| 13 | Provisionar/desprovisionar | `/admin/evolution/provision` e `/deprovision` por SSH | sem provisionamento por tenant; `connect`/`disconnect` no gateway | n/a (arquitetura muda) |
| 14 | Ligacao com agente de IA/fila | via `Channel::EvolutionApi` + Agent Bot | via `Channel::WhatsappUnofficial` (mesmo miolo dos demais) | pendente de teste conjunto |

## B. Exigido pelo CH-10 (alem do que o Evolution faz hoje)
| # | Item | Observacao | Status |
|---|---|---|---|
| 15 | Midia (imagem, audio, video, documento) nos dois sentidos | o Evolution do Luar hoje trata **so texto**; paridade aqui e "igualar ou superar" | pendente de teste conjunto |
| 16 | Grupos | idem (nao tratados hoje) | pendente de teste conjunto |
| 17 | Resposta (quote) e reacao | idem | pendente de teste conjunto |
| 18 | Edicao/exclusao | so se o CH-0 provar | pendente de teste conjunto |
| 19 | Reconexao automatica (rede cai, bridge reinicia) sem novo QR | restart preserva login | pendente de teste conjunto |
| 20 | Historico (2 meses) sem duplicar | janela `BACKFILL_DAYS=60` | pendente de teste conjunto |
| 21 | 2 contas no mesmo processo sem cruzar mensagens | isolamento | pendente de teste conjunto |
| 22 | RAM por conta medida | meta: bem abaixo de 3 containers por tenant | pendente de teste conjunto |
| 23 | `Channel::Wapi` permanece | outro provedor, fora do escopo | n/a |

## C. Criterio de aceite
Todas as linhas A e B em **PASS** (ou "n/a" justificado) na `anexos/10/CH-10.md`, com numero de teste do dono; so entao o dono aprova a aposentadoria do Evolution (`MIGRACAO_WHATSAPP.md`). Ate la, Evolution **convive** e nada e desligado.
