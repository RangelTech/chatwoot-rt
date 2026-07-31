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
3. Permissões necessárias: `pages_messaging`, `pages_manage_metadata`,
   `pages_show_list`, `instagram_basic`, `instagram_manage_messages`.
4. Webhook do Messenger/Instagram apontando para:
   `https://<chatwoot-web>/webhooks/facebook` e `.../webhooks/instagram`,
   com o mesmo *verify token* que você vai guardar abaixo.

## 2. Guardar os segredos

```bash
printf '%s' "<app id>"        | gcloud secrets create chatwoot-meta-app-id      --data-file=- --project=eduk-prd-lake
printf '%s' "<app secret>"    | gcloud secrets create chatwoot-meta-app-secret  --data-file=- --project=eduk-prd-lake
printf '%s' "<verify token>"  | gcloud secrets create chatwoot-meta-verify-token --data-file=- --project=eduk-prd-lake

for s in chatwoot-meta-app-id chatwoot-meta-app-secret chatwoot-meta-verify-token; do
  gcloud secrets add-iam-policy-binding "$s" --project=eduk-prd-lake \
    --member=serviceAccount:devlake@eduk-prd-lake.iam.gserviceaccount.com \
    --role=roles/secretmanager.secretAccessor
done
```

O `deploy.sh` injeta esses segredos **se existirem**. Enquanto não existirem, o
Chatwoot sobe sem os canais Meta — não quebra.

## 3. Publicar

```bash
./infra/deploy.sh chatwoot
```

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
- Um app compartilhado significa que um bloqueio da Meta afeta todos os tenants:
  é o custo aceito por não exigir app por cliente.
