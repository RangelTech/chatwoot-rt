# Migracao do WhatsApp nao oficial: Evolution -> mautrix-whatsapp

Decisao do dono (20/10/2026): o WhatsApp nao oficial passa a ser o `mautrix-whatsapp` (login por QR), no lugar do Evolution. **Convivencia ate a paridade comprovada; nada apagado antes do U-7.** `Channel::Wapi` fica.

## Fases
1. **Preparar (sem mexer em producao)**: pilha `canais` com `mautrix-whatsapp` (porta de provisionamento 29318) revisada; gateway com provedor `whatsapp`; `Channel::WhatsappUnofficial`. Nenhum canal existente e tocado.
2. **Provar**: com numero de teste do dono, preencher `PARIDADE_EVOLUTION.md` (CH-0f/CH-10): QR e codigo de pareamento, texto, midia, grupos, resposta, reacao, reconexao, historico de 60 dias, 2 contas sem cruzar, RAM por conta.
3. **Convivencia**: o assistente "Conectar canal" passa a oferecer WhatsApp Experimental (mautrix). Canais Evolution existentes continuam funcionando.
4. **Migrar canal a canal (por release)**: para cada caixa Evolution, o administrador **reconecta por QR** no assistente (o pareamento do Evolution **nao migra**). A mesma caixa de entrada/conversas/contatos e mantida; o historico novo vem pela janela de 60 dias **sem duplicar** (`source_id`). Janela combinada com o cliente; um canal por vez.
5. **Aceite do dono**: paridade em PASS + canais migrados.
6. **Aposentar sem apagar**: parar (nao remover) os containers `evolution-*`, `evolution-pg-*`, `evolution-redis-*`; **os volumes ficam guardados** (`/opt/platform/data/evolution-pg-*` com backup); desligar `/admin/evolution/*` e a rota `Webhooks::EvolutionController` por flag. Remocao fisica so no U-7, com backup e aceite.

## Rollback
Enquanto os containers Evolution existirem, voltar = reativar o canal Evolution (QR novo no Evolution) e `revogar` a conexao mautrix. Depois de parado: religar os containers (volumes intactos) e reparear por QR.

## Cuidados
- Um numero nao pode estar ativo nos dois lados ao mesmo tempo sem aviso: o WhatsApp limita aparelhos vinculados e o segundo pareamento pode derrubar o primeiro. Migrar fora do horario de pico.
- Aviso de risco e consentimento (versao `risk-2026-10-v1`) exibidos na reconexao.
- Numero banido = numero do cliente; recomendar o canal oficial.
- Backups: `backup.sh` ja inclui `evolution-pg-*`; conferir o ultimo antes de parar qualquer container.

## Checklist por canal migrado
- [ ] Backup recente (<24 h) e restore ensaiado.
- [ ] Cliente avisado e aceitou o aviso de risco.
- [ ] QR lido, `connected`, mensagem de teste nos dois sentidos.
- [ ] Historico sincronizado sem duplicata.
- [ ] Agente/fila (Fase F) reapontados para a nova caixa.
- [ ] Caixa Evolution antiga marcada como legado (somente leitura), sem apagar.
