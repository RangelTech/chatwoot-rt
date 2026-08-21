# Manutenção do fork `chatwoot-rt`

O fork mantém customizações pequenas e rastreáveis para que upgrades do
Chatwoot não dependam de memória informal. O contrato executável está em
[`chatwoot/fork_extensions.yml`](../../chatwoot/fork_extensions.yml) e é
validado por `scripts/verify_fork_extensions.rb`.

## Limites das extensões

| Família | Estratégia | Touchpoints upstream que exigem revisão |
| --- | --- | --- |
| AI Assist `api_base` | patch pequeno | `llm_base_service`, validador OpenAI e definição da integração |
| `Channel::Wapi` | arquivos aditivos + pontos de registro | `Account`, controller/helper de inbox e rota de webhook |
| Evolution API | arquivos aditivos + estado persistido | `Account`, inbox API/helper, envio de resposta e rota de webhook |
| Branding e entrypoints | overlay/entrypoints próprios | `Dockerfile` e scripts RT |

Arquivos de canais devem permanecer aditivos. Alterações em arquivos do core
precisam entrar no manifest como `touchpoints`, junto de um marcador que torne
visível uma remoção acidental durante rebase ou upgrade.

## Checklist de upgrade

1. Crie uma branch de upgrade e atualize `upstream_version` no manifest para a
   versão que será adotada.
2. Faça o merge/rebase do upstream e resolva conflitos sem apagar os arquivos
   aditivos do fork.
3. Rode o contrato abaixo. Ele confere arquivos, touchpoints e marcadores das
   extensões ativas; Evolution é mostrado como `SKIP` até existir.
4. Rode as specs da família modificada (AI Assist ou WAPI) e construa a imagem
   Docker do Chatwoot no pipeline de upgrade.
5. Atualize o manifest e este documento se algum touchpoint mudar. Só então
   abra o PR de upgrade.

```bash
ruby scripts/verify_fork_extensions.rb
docker build -f chatwoot/Dockerfile .
```

Em uma máquina sem Ruby instalado, o primeiro comando pode ser executado com
Docker:

```bash
docker run --rm --mount type=bind,source="$PWD",target=/workspace,readonly \
  --workdir /workspace ruby:3.3-alpine ruby scripts/verify_fork_extensions.rb
```

## Specs de regressão por família

```bash
# AI Assist
bundle exec rspec chatwoot/spec/lib/integrations/llm_base_service_spec.rb

# WAPI
bundle exec rspec chatwoot/spec/models/channel/wapi_spec.rb \
  chatwoot/spec/controllers/webhooks/wapi_controller_spec.rb \
  chatwoot/spec/jobs/webhooks/wapi_events_job_spec.rb \
  chatwoot/spec/requests/api/v1/accounts/inboxes_wapi_spec.rb

# Evolution API
bundle exec rspec chatwoot/spec/models/channel/evolution_api_spec.rb \
  chatwoot/spec/jobs/webhooks/evolution_events_job_spec.rb
```

O validador é deliberadamente independente de Rails e gems do aplicativo:
assim ele pode ser executado antes do build completo e também no CI.
