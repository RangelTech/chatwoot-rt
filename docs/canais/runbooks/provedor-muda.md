# Runbook: o provedor mudou ou bloqueou (Meta, TikTok, WhatsApp)

Canais experimentais dependem de protocolos nao documentados. Mudanca e bloqueio **vao acontecer**; o objetivo e degradar com clareza, sem perder dado e sem agravar o bloqueio.

## Sinais
- Muitos canais ao mesmo tempo em `degraded` / `reauth_required` / `provider_unavailable`; erros de login novos (`unsupported_step`, `checkpoint_required`); queda de entrega; log do bridge com erro de protocolo.
- Aviso na pagina de issues do upstream (mautrix, ReLttk).

## Triagem (30 min)
1. Escopo: um tenant (conta bloqueada) ou todos (protocolo mudou)? Um provedor ou varios?
2. Upstream: ha issue/release de correcao? (`mautrix/meta`, `mautrix/whatsapp`, ReLttk).
3. **Parar de insistir**: desligar tentativas automaticas do canal afetado (o gateway ja limita tentativas; nao aumentar). Nunca criar rotina de re-login agressivo.

## Acoes
| Caso | Acao |
|---|---|
| Uma conta bloqueada/pedindo verificacao | avisar o cliente; ele resolve no app oficial; reconectar so depois (`reconectar.md`) |
| Protocolo mudou, upstream corrigiu | ciclo extraordinario de `atualizar-bridge.md` (ensaio em conta de teste, depois promover) |
| Protocolo mudou, sem correcao | marcar o provedor **indisponivel** no catalogo do assistente (aviso em PT-BR/EN); manter historico; oferecer o caminho **Oficial** (Meta/TikTok API) quando existir |
| Provedor proibiu/ameacou contas | suspender o provedor experimental (flag por Account/global), comunicar o dono, rever `RISCOS_E_TERMOS.md` |
| WhatsApp: numero banido | numero do cliente; nao reutilizar; recomendar o canal oficial (Wapi/Cloud API) |

## Nunca
Burlar 2FA, CAPTCHA, verificacao de identidade ou protecao do provedor; trocar IP/fingerprint para escapar de bloqueio; pedir cookie.

## Depois
Registrar o incidente (data, provedor, causa, tempo ate normalizar); atualizar `MATRIZ_VERSOES.md` e o aviso de risco se o quadro mudou.
