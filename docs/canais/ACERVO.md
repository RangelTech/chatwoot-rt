# Acervo anterior dos canais nao oficiais

Indice das referencias recuperadas em 20/10/2026 (Spec 10, Fase CH, "Acervo anterior do dono"). Copias **redigidas** (cookies, tokens, senhas, hashes longos, e-mails e identificadores de conta removidos) em `docs/canais/acervo/`. Os originais ficam no clone `personal-skills` do dono; **nunca** copiar cookies ou payloads reais para este repositorio.

| # | Referencia | O que e / por que importa | Copia redigida |
|---|---|---|---|
| 1 | `personal-skills/mega-spec-reestrutura/correcao-01-execucao-completa.md` §4 e §5 (28/08/2026) | Decisao Matrix + mautrix-meta em vez de Ruby/Playwright; 2 processos compartilhados ("puppeting", nao *relay bot*); sem limite de contas; 1 inbox por conexao; historico de 2 meses; validacao real; **3 problemas de infraestrutura** | `acervo/correcao-01-execucao-completa.md` |
| 2 | `personal-skills/mega-spec-reestrutura/memoria.md`, secao "28/08/2026 — MATRIX EM PRODUCAO DE VERDADE" | Registro da subida real na VPS (Facebook e Instagram logados) | `acervo/memoria_2026-08-28_matrix_em_producao.md` (so a secao) |
| 3 | `.../concluidas/produto-15-ratende-connector-extensao.md` | A extensao de navegador `ratende-connector` que captura cookies (**substituida** pela Fase CH; repo recebe aviso DESCONTINUADO na Fase R) | `acervo/produto-15-ratende-connector-extensao.md` |
| 4 | `.../concluidas/lab-02-cookies-connector-vs-canais-unofficial.md` | Comparacao conector por cookies x `Channel::*Unofficial` do Chatwoot (as duas mecanicas que nao se conversam) | `acervo/lab-02-cookies-connector-vs-canais-unofficial.md` |
| 5 | `.../concluidas/produto-08-credenciais-oauth-navegador-remoto.md` | O navegador remoto espelhado (caminho abandonado) | `acervo/produto-08-credenciais-oauth-navegador-remoto.md` |
| 6 | `.../concluidas/tiktok-dm-estudo-completo.md` (28/08) | Conclusao: nenhuma biblioteca aberta lia/enviava DM por cookie+HTTP; endpoint de DM nunca encontrado. **O ReLttk fecha a lacuna** (a provar no CH-0c) | `acervo/tiktok-dm-estudo-completo.md` |
| 7 | `<acervo-pessoal>/scratchpad/login_tiktok_isolado.py` | Login TikTok por navegador automatizado + cookie (caminho **antigo**) | `acervo/login_tiktok_isolado.py.txt` |
| 8 | `Desktop/<acervo-pessoal>/vps_rt_infra_matrix_test/` | Ambiente de teste que **ja funcionou** (Synapse + `matrix-postgres` + `mautrix-meta` `latest`/`ig-latest`). **Base do CH-0**: troca o login por cookie por usuario/senha e QR. `fb_payload.json`/`ig_payload.json` = cookies minimos | `acervo/matrix_test_docker-compose.yml`; `acervo/matrix_test_payloads_so_nomes.md` (somente nomes dos campos) |
| 9 | `Desktop/arquitetura_canais_chatwoot_mautrix_tiktok.md` (17/10/2026) | PRD tecnico: projetos e links primarios, estados, entidades, fluxos, criterios de aceite, prompt de handoff. Sem segredos | referencia (nao copiado; vive no repositorio de specs) |

## Links primarios (da pesquisa de 17/10)
- mautrix/meta: https://github.com/mautrix/meta (changelog e docs de autenticacao em https://docs.mau.fi/bridges/go/meta/authentication.html)
- ReLttk: https://github.com/Linkmail16/ReLttk-TikTok-Client-Bot (MIT)
- beeper/chatwoot (referencia para o adaptador Matrix -> Chatwoot, Apache-2.0)
- armxe/tiktok-api (assinatura `X-Bogus`/`X-Gorgon`, alternativa)
- TikTok Business Messaging API (oficial): https://business-api.tiktok.com/portal/docs/business-messaging-api-get-started/v1.3
- Correcao de pesquisa: o `tgbot` (self-DM -> Telegram) **nao** e bridge geral de atendimento; so referencia de transporte.

## Ligacao com a Fase CH
- Os 3 problemas de infra do item 1 estao resolvidos em `vps_rt_infra/stacks/canais` (config do Synapse em `/etc/synapse`; rede `canais_egress`; `chown 999:999`).
- O que a validacao de 28/08 **nao provou** e a Fase CH precisa provar: 2 contas reais do mesmo tipo no mesmo processo; o adaptador Matrix -> Chatwoot (gateway proprio, opcao B, estudando `beeper/chatwoot`); qualquer login sem cookie.
- Politica herdada: historico das migracoes = **ultimos 2 meses** (60 dias).
- Destino final destas copias: `luar_docs` (R-7).
