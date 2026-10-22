# Retencao de dados e consentimento (LGPD) — canais experimentais

Rascunho **revisavel pelo dono**; nao substitui parecer juridico/DPO.

## 1. Dados tratados
| Dado | Onde fica | Finalidade | Retencao proposta |
|---|---|---|---|
| Usuario e senha digitados no assistente | **nao ficam**: navegador -> Rails (HTTPS) -> gateway (chamada sincrona) -> bridge; nao gravados, nao logados, nunca em Sidekiq/Redis | autenticar no provedor | 0 (em memoria, durante o passo) |
| Sessao do provedor (token/cookie interno) | somente banco do bridge (mautrix) ou diretorio do worker TikTok | manter a conexao | enquanto `connected`; removida em `disconnect/revoke` (TikTok: movida para quarentena e apagada apos prazo, com backup e aceite) |
| Mensagens e contatos (conversas) | Chatwoot (fonte oficial) | atendimento | politica do contrato do cliente; **nunca apagar automaticamente** |
| Copia transitoria no Matrix (Synapse) | `matrix-postgres`, `media_store` | transporte | midia: 14 d (remota) / 90 d (local); eventos: ver limpeza do Synapse; historico oficial nao depende dela |
| Idempotencia `rt_channel_messages` | Postgres da bridge | evitar duplicata | enquanto a conversa existir (sem texto, so IDs) |
| Auditoria `rt_channel_audit` | Postgres da bridge | quem conectou/desconectou/reautenticou, **consentimento aceito (versao, data, ator)** | 5 anos (prova de consentimento) — confirmar com juridico |
| Logs | Loki/Docker | operacao | 30 dias; **sem** credenciais |
| Historico sincronizado | Chatwoot | migracao | **ultimos 60 dias** (janela padrao permanente; configuravel) |
| Backups | restic/Drive criptografado | recuperacao | conforme `backup.sh`; sessoes dentro de backup criptografado |

## 2. Base legal e papeis (a confirmar)
Cliente = controlador dos dados das conversas; Rangel Tech = operador. Base legal do cliente: execucao de contrato/legitimo interesse no atendimento. O titular da **conta conectada** (quem digita a senha) consente expressamente com o uso do canal experimental e seus riscos.

## 3. Direitos do titular
Acesso, correcao, eliminacao, portabilidade: atendidos pelo cliente com apoio do Luar. Eliminacao: **procedimento com backup e aceite**, nunca automatico. Revogacao do consentimento = `desconectar/revogar` (para a coleta; historico segue a politica do contrato).

## 4. Incidentes
Vazamento de sessao: `runbooks/vazamento-sessao.md`; avaliar comunicacao a ANPD e titulares no prazo legal.

## 5. Aviso de risco exibido no assistente (texto revisavel)
Registrado na auditoria com `versao`, data, usuario e conta. Mudou o texto = nova versao e novo aceite.

### PT-BR (versao `risk-2026-10-v1`)
> **Conexao experimental (nao oficial)**
> Esta conexao entra na sua conta usando o mesmo acesso de um aplicativo comum, sem a API oficial da plataforma. Isso **pode violar os termos de uso** do Instagram/Messenger/TikTok/WhatsApp e a plataforma **pode limitar, bloquear ou banir a conta ou o numero**, ou parar de funcionar sem aviso.
> - Use uma conta sua ou de teste; nao use a conta principal da sua empresa se nao puder perde-la.
> - **Nao desative a verificacao em duas etapas (2FA).**
> - Sua senha e usada so para entrar e **nao e guardada** pelo Luar. A sessao fica protegida no servidor e voce pode **desconectar a qualquer momento**.
> - As mensagens aparecem na sua caixa de entrada e seguem a politica de privacidade do servico.
> - Existe uma opcao **Oficial** (API da plataforma), mais estavel e permitida.
> [ ] Entendi os riscos e autorizo esta conexao experimental.

### EN (version `risk-2026-10-v1`)
> **Experimental (unofficial) connection**
> This connection signs in to your account the way a regular app does, without the platform's official API. This **may violate the terms of service** of Instagram/Messenger/TikTok/WhatsApp, and the platform **may restrict, block or ban the account or number**, or stop working without notice.
> - Use your own or a test account; do not use a business-critical account you cannot afford to lose.
> - **Do not turn off two-factor authentication (2FA).**
> - Your password is used only to sign in and is **not stored** by Luar. The session is protected on the server and you can **disconnect at any time**.
> - Messages appear in your inbox and follow the service privacy policy.
> - An **Official** option (the platform's API) exists and is more stable and permitted.
> [ ] I understand the risks and authorize this experimental connection.

## 6. Pontos para o dono decidir
Prazo de retencao da auditoria; prazo de quarentena das sessoes TikTok; politica de eliminacao de historico; quem e o DPO/contato.
