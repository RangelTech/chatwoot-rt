# Runbook — Instagram e Facebook (Meta App compartilhado)

A decisão da Fase 2 é **um único Meta App por instalação**: cada empresa conecta
a própria página dentro dele, em vez de cada uma criar e revisar um app próprio.
Isso troca burocracia por responsabilidade centralizada — a governança do app,
das permissões e do webhook é nossa.

> **Ativar canal real com cliente real exige checkpoint humano** (regra 5.5 da
> Fase 2). Este runbook prepara tudo; a conexão de uma página de produção é
> decisão explícita do dono do produto.

## 1. Preparar o Meta App (uma vez por instalação)

No painel de desenvolvedores da Meta:

1. Crie um app do tipo *Business*.
2. Adicione os produtos **Messenger** e **Instagram**.
3. Para Messenger, a conexão da Página deve conceder `pages_show_list`,
   `pages_read_engagement` e `pages_messaging`. A assinatura criada pelo
   Chatwoot deve conter `messages`, `message_deliveries`, `message_echoes`,
   `message_reads`, `standby` e `messaging_handovers`.
4. O callback do **Messenger** é `https://chat.rangeltech.net/bot`. A Meta o
   valida por `GET` com o verify token e entrega mensagens por `POST` no mesmo
   endereço. Não configure `/webhooks/facebook`: ele não é a rota do servidor
   Messenger deste fork.
5. Para Instagram Business Login, cadastre a URL de redirecionamento exata
   `https://chat.rangeltech.net/instagram/callback` e siga o wizard do
   Chatwoot. O webhook Instagram é configurado no produto Instagram da Meta.

Enquanto o app estiver em modo desenvolvimento, a Meta entrega eventos apenas
de contas com papel no app (admin, developer ou tester). A Caixa de Entrada da
Meta receber uma mensagem não prova que o webhook chegará ao Chatwoot. Para
validar antes da publicação, envie a mensagem de uma conta com papel no app e
confirme o evento no Chatwoot.

## 2. Guardar os segredos

Os segredos Meta vivem exclusivamente no projeto `chatwoot-prod` do
**Infisical**, ambiente `prod`: `FB_APP_ID`, `FB_APP_SECRET`,
`FB_VERIFY_TOKEN`, `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET` e
`INSTAGRAM_VERIFY_TOKEN`.

Os workflows de deploy os buscam por Universal Auth e os aplicam tanto no Cloud
Run quanto no worker Sidekiq da VPS. O worker também sincroniza o
`InstallationConfig` do Chatwoot. Nunca coloque esses valores em GitHub
Variables, comandos versionados, código ou neste runbook.

Para trocar uma credencial, atualize o Infisical e redeploye os dois destinos.
O deploy deve falhar se algum segredo obrigatório estiver ausente, em vez de
subir com valor vazio ou antigo.

## 3. Publicar

Use os workflows **Deploy chatwoot-web to Cloud Run** e **Deploy Chatwoot
worker to VPS** para aplicar a mesma revisão nos dois destinos.

## 4. Conectar a página de uma empresa

Quem faz isso é a própria empresa, dentro da conta dela no Chatwoot:
*Settings → Inboxes → Add Inbox → Facebook/Instagram*, autorizando a página.
O isolamento continua valendo: a inbox nasce dentro da `Account` daquele tenant.

## 5. IA nesses canais

A ponte não muda: o Agent Bot já está associado por inbox. Para a IA atender
também o Instagram/Facebook de um tenant, registre a config apontando para a
nova inbox:

```bash
curl -X POST "$BRIDGE_URL/admin/ai-config" \
  -H "Authorization: Bearer $BRIDGE_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"tenant_id":"<uuid>","chatwoot_inbox_id":<id da inbox meta>,
       "integration_key":"<chave>","autopilot":true}'
```

A saída dessas conversas é nativa do Chatwoot (ele fala com a Meta direto), então
o `/outbound` da ponte — que existe para o WhatsApp via W-API — não participa.

## Limites conhecidos

- **Janela de 24h** do Messenger/Instagram: fora dela, só template aprovado.
- **App review** da Meta é requisito para sair do modo de desenvolvimento.
- `pages_messaging` precisa de aprovação/Advanced Access para mensagens de
  usuários comuns no Messenger. Instagram requer as permissões de mensagens
  aprovadas e app em modo Live.
- Um app compartilhado significa que um bloqueio da Meta afeta todos os tenants:
  é o custo aceito por não exigir app por cliente.
