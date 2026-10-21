# Riscos e termos dos provedores (canais experimentais)

Documento de trabalho para o dono. **Nao e parecer juridico**; os termos citados devem ser relidos e validados por advogado antes de uso comercial com clientes finais.

## 1. Natureza do risco
Instagram, Messenger, TikTok e WhatsApp experimentais usam **clientes nao oficiais** (protocolos internos/engenharia reversa). Os provedores **podem**: bloquear ou limitar a conta, pedir verificacao repetida, derrubar sessoes, alterar o protocolo sem aviso, tratar o uso como violacao dos termos. Nenhum login remoto elimina verificacoes; IP de datacenter, localizacao e fingerprint continuam diferentes do aparelho do usuario.

| Provedor | Exposicao | Observacao |
|---|---|---|
| WhatsApp | alto (banimento do numero) | os termos do WhatsApp vedam clientes nao oficiais/automacao nao autorizada; o numero e do cliente |
| Instagram / Messenger (Meta) | medio a alto (restricao/checkpoint da conta) | termos da Meta vedam acesso automatizado fora das APIs; login `android` imita o app |
| TikTok | alto e pouco conhecido | ReLttk usa WebSocket/protobuf interno e assinatura de requisicao; estabilidade nao provada; **nao ha canal oficial equivalente para DM de perfil pessoal** |

Mitigacoes: consentimento explicito e registrado; "use uma conta sua/de teste"; **nao desative o 2FA**; limites de taxa e de tentativas conservadores; *circuit breaker*; sem reconexao agressiva; caminho **Oficial** sempre oferecido ao lado; possibilidade de desligar o provedor inteiro por flag.

## 2. Licencas dos componentes
| Componente | Licenca | Como usar | Obrigacao |
|---|---|---|---|
| mautrix/meta (Messenger, Instagram) | **AGPL-3.0** | **usar sem modificar**: so imagem oficial por tag+digest e configuracao | manter aviso e indicar a origem do codigo-fonte; se um dia modificarmos o codigo do bridge, oferecer o codigo-fonte aos usuarios da rede (AGPL §13) — **decisao do dono antes** |
| mautrix/whatsapp | **AGPL-3.0** | idem | idem |
| Synapse | AGPL-3.0 (ou licenca comercial Element) | uso interno, privado, sem federacao, sem modificar | idem; nao expor publicamente |
| ReLttk-TikTok-Client-Bot | **MIT** | instalar por commit fixado; nao copiar o codigo para dentro do repositorio | manter o aviso de copyright/licenca MIT junto da imagem |
| beeper/chatwoot (referencia) | Apache-2.0 | apenas leitura/inspiracao; trechos reaproveitados exigem aviso | manter NOTICE |
| armxe/tiktok-api (alternativa de assinatura) | conferir antes de adotar | n/a | n/a |

Nosso gateway conversa com os bridges **pela rede/HTTP** (API de provisionamento e Matrix), sem ligar o codigo AGPL ao nosso: reduz o risco de "obra derivada". Confirmar com advogado.

## 3. Riscos tecnicos e operacionais
- Dependencia de projetos de poucos mantenedores (ReLttk: um autor, 15 estrelas) e de assinatura de terceiros: pode parar a qualquer momento. Tratar TikTok como **experimental**.
- Migracoes de banco do bridge sao **sem volta**: backup + restore ensaiado antes de atualizar.
- Isolamento entre tenants depende de configuracao (um usuario Matrix por conexao + namespace do appservice): provado por testes de autorizacao negativa (CH-11); plano B = um processo por tenant.
- Mensagens criptografadas do Messenger: suporte e limites a provar (CH-0e).
- Sessao = credencial: guardar so no bridge/worker, nunca no Luar; segredo fora de logs.

## 4. Responsabilidades
- O **cliente** e dono da conta/numero e assume o risco de uso do canal experimental (texto de consentimento do cliente final pertence ao fluxo de assinatura do servico, outro escopo).
- A Rangel Tech nao garante disponibilidade dos canais experimentais; oferece o caminho oficial e reconexao guiada.
- Canais reais de clientes so entram com o dono liberando (Q13); ate la, so contas de teste.

## 5. Pendencias para o dono
1. Aprovar a politica "usar AGPL sem modificar" e o gatilho de revisao (se modificar o bridge).
2. Revisar o texto de aviso (`RETENCAO_E_CONSENTIMENTO.md`) com advogado.
3. Decidir se TikTok experimental e oferecido a clientes ou so interno.
