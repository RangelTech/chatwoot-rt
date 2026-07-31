# Branding e empacotamento comercial

## Branding sem fork

O que dá para mudar sem tocar no código do Chatwoot:

| O quê | Onde |
|---|---|
| Nome da instalação, logo, favicon | Super Admin → Settings (`INSTALLATION_NAME`, `BRAND_NAME`, `LOGO`) |
| Domínio próprio | `FRONTEND_URL` + mapeamento de domínio no Cloud Run |
| Assets adicionais | `chatwoot/branding/` → servido em `/brand-assets/` |
| Remetente e domínio de e-mail | `MAILER_SENDER_EMAIL`, `SMTP_*` |
| Cor de destaque por conta | configuração da própria `Account` |

O que **não** fazemos: alterar componentes Vue, rotas ou telas do Chatwoot. O
dia em que isso for inevitável, vira decisão registrada com o custo explícito de
manter merge com o upstream — é exatamente o que a Fase 2 decidiu evitar.

A marca principal continua sendo a do agent-platform: o operador entra por lá,
clica em *Atendimento* e cai no Chatwoot já logado. O Chatwoot é a mesa de
trabalho, não a fachada.

## Planos e o que muda em cada um

Os limites são de produto, não de infraestrutura — o isolamento por tenant é o
mesmo em todos.

| Plano | Canais | IA | Operação |
|---|---|---|---|
| Essencial | 1 número de WhatsApp | responde sozinha; handoff só por pedido explícito | 1–2 atendentes |
| Profissional | WhatsApp + Instagram + Facebook | IA com template dedicado por inbox | times, filas e distribuição |
| Sob medida | vários números/páginas | template por canal, tools e datasources próprios | times múltiplos, SLA e relatórios |

Duas coisas valem para todos os planos, porque são segurança e não diferencial:
credenciais cifradas por tenant e uma `Account` do Chatwoot por empresa.

## Cenários que a arquitetura já atende

1. **Hamburgueria (Fase 1, Fase C)** — o cliente pede pelo WhatsApp, a IA
   consulta cardápio e grava o pedido, gera a cobrança PIX (Fase D) e chama um
   humano quando o pedido foge do padrão.
2. **Atendimento com transbordo** — a IA resolve o repetitivo; assim que um
   atendente escreve, ela se cala na hora (estado `human_active`).
3. **Operação multi-marca** — uma empresa com duas marcas usa dois tenants, e
   nenhuma conversa ou credencial cruza entre elas.

## O que ainda não está pronto

- Enviar cobrança PIX formatada (QR + copia-e-cola) pelo WhatsApp: a tool já
  gera a cobrança, falta a camada de entrega interpretar o artifact.
- Fila persistente para reprocessar eventos em massa (hoje é `BackgroundTasks`
  em processo, com o corpo cru guardado para replay manual).
- Relatórios comerciais consolidados entre plataforma e atendimento.
