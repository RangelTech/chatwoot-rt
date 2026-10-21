# Runbook: reconectar um canal (`reauth_required`)

**Quando:** a caixa de entrada mostra "Reconexao necessaria" (`reauth_required`), ou o cliente avisa que parou de receber. Vale para Instagram, Messenger, TikTok e WhatsApp experimentais.
**Regra:** nunca pedir cookie, nunca pedir para desativar o 2FA, nunca repetir login em rajada (limite de tentativas por conta: 5/h; por tenant: 20/h).

## Quem faz
O administrador da conta, pelo Luar: caixa de entrada -> **Reconectar**. O suporte nao tem acesso a senha nem a sessao.

## Passo a passo (usuario)
1. Abrir a caixa de entrada afetada -> painel de estado -> **Reconectar** (abre o mesmo assistente da criacao; conversas e historico ficam).
2. Instagram/Messenger: usuario e senha -> codigo 2FA se pedido -> se aparecer "confirme no aplicativo", aprovar no celular e aguardar.
3. TikTok: escanear o QR (TikTok -> Perfil -> menu -> Codigo QR); renova sozinho; codigo de verificacao se pedido.
4. WhatsApp: QR ou codigo de pareamento (WhatsApp -> Aparelhos conectados).
5. Esperar "Validando acesso" e a sincronizacao das conversas recentes (janela padrao: 60 dias, sem duplicar).

## Se falhar (operador)
| Sintoma (`error_code`) | Causa provavel | Acao |
|---|---|---|
| `wrong_password` / `wrong_code` | digitacao | tentar de novo (sem passar do limite) |
| `checkpoint_required` / `account_locked` | a plataforma pede verificacao | o dono da conta resolve no app oficial; esperar 24 h; **nao** repetir |
| `too_many_attempts` | limite do gateway | esperar a janela (1 h); nao burlar |
| `provider_unavailable` / `unsupported_step` | provedor mudou o fluxo | ver `provedor-muda.md` |
| `timeout` | QR/2FA expirou | recomecar |

## Conferencias
- Estado vai a `connected`; `last_activity_at` atualiza; uma mensagem de teste entra e sai.
- Auditoria `rt_channel_audit` registra quem reautenticou (sem credenciais).
- Se a reconexao repetir a cada poucas horas: abrir incidente, tratar como sinal de bloqueio pelo provedor.
