# Matriz de versoes dos canais nao oficiais

Fonte unica das versoes **fixadas**. Espelha `vps_rt_infra/stacks/canais/versions.env`. Nunca `latest`. Digest = preenchido por `scripts/resolve_digests.sh` (enquanto `DIGEST_A_PREENCHER`, nao ha deploy). Atualizar esta tabela a cada ciclo mensal (`runbooks/atualizar-bridge.md`).

| Componente | Imagem / origem | Tag fixada | Digest | Licenca | Login exposto (a confirmar no CH-0a) | Porta de provisionamento | Verificado em |
|---|---|---|---|---|---|---|---|
| mautrix-meta (Messenger) | `dock.mau.dev/mautrix/meta` | `v26.10` (upstream `v0.2610.0`, 16/10/2026) | `DIGEST_A_PREENCHER` | AGPL-3.0 (sem modificar) | `messenger-lite` (usuario/senha + 2FA); modos mobile iOS/Android | 29319 | pendente (CH-0) |
| mautrix-instagram | `dock.mau.dev/mautrix/meta` | `ig-v26.10` | `DIGEST_A_PREENCHER` | AGPL-3.0 (sem modificar) | `android` (usuario/senha + 2FA); NAO usar `instagram-password` (webview) nem cookies | 29319 | pendente (CH-0) |
| mautrix-whatsapp | `dock.mau.dev/mautrix/whatsapp` | `v26.10` | `DIGEST_A_PREENCHER` | AGPL-3.0 (sem modificar) | QR e codigo de pareamento | 29318 | pendente (CH-0f) |
| Synapse (privado) | `matrixdotorg/synapse` | `v1.159.0` (em uso desde 28/08) | `DIGEST_A_PREENCHER` | AGPL-3.0 / comercial Element (so uso interno, sem modificar) | n/a | 8008 (so rede interna) | pendente |
| PostgreSQL do Matrix | `postgres` | `16` | `DIGEST_A_PREENCHER` | PostgreSQL | n/a | 5432 (so rede interna) | pendente |
| ReLttk (TikTok) | `Linkmail16/ReLttk-TikTok-Client-Bot` | commit fixado dentro da imagem do worker (`COMMIT_A_PREENCHER`, ultimo upstream 15/10/2026) | imagem `luar-tiktok-worker`: `DIGEST_A_PREENCHER` | MIT | QR (+2FA/verificacao, corrigido em 12/10/2026) | n/a (worker fala com o gateway) | pendente (CH-0c) |
| Assinatura TikTok (alternativa) | `armxe/tiktok-api` | nao adotada | n/a | conferir | n/a | n/a | avaliar no CH-0c |
| Gateway de canais | `luar_chatwoot/bridge` (`app/channels`) | versao da release do `chatwoot-bridge` | por lock | proprietaria | n/a | interna | por release |

## Regras
- Tag so muda junto com o digest e com a linha desta tabela, em PR proprio.
- Imagens `ig-` e sem prefixo vem do mesmo repositorio (`mautrix/meta`) e devem andar **na mesma versao**.
- Dois ciclos sem atualizar um bridge = revisar risco (o upstream acompanha mudancas do provedor).
- Versoes anteriores (28/08/2026, `latest`/`ig-latest`, cookies) estao **aposentadas**; nao reutilizar.
- Evolution API (`evoapicloud/evolution-api:v2.3.7`): convive ate a paridade (ver `PARIDADE_EVOLUTION.md`), depois parado sem apagar volumes.

## Digests aplicados na VPS (21/10/2026)
| Imagem | Tag | Digest |
|---|---|---|
| mautrix-meta (Messenger) | v26.10 | sha256:22bfa54084b6855188f5146b325ee007a298443a9617caead06cc5fc0ba0d687 |
| mautrix-instagram | ig-v26.10 | sha256:a65249320ab4fba15587b77b9aa7d4024e4ff3e68ade1077da6000a899abbf26 |
| mautrix-whatsapp | v26.10 | sha256:c807054cb015d0f5c90d20d85aac216d062b4a6f4ae834b931fd5e7f03e27391 |
| Synapse | v1.159.0 | sha256:edf259d2b575b669a3e81024918ab8d5cfb7d2fba5a53c9e09695f1abc5645cb |
| postgres | 16 | sha256:a902560563d3a5661228585f53474c5065e7f273b21ffd77e555a8b5682c5690 |
| ReLttk (dentro do chatwoot-bridge) | commit 6483b27f441aaf13ebb3ad82b4c49014216a9733 (15/10/2026) | MIT; pip: websockets lz4 qrcode stealth-requests pycryptodome |
