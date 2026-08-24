"""Resolução de tenant e estado operacional.

Regra de ouro desta camada: **nada é lido ou escrito antes de o tenant estar
resolvido**. Toda função aqui recebe ou devolve o tenant explicitamente — é o
que impede uma mensagem de um cliente aparecer na conta de outro.
"""

import secrets

from app.crypto import decrypt, encrypt
from app.db import get_connection


def upsert_tenant_link(*, tenant_id: str, tenant_key: str, tenant_name: str) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """INSERT INTO tenant_links (tenant_id, tenant_key, tenant_name)
               VALUES (%s, %s, %s)
               ON CONFLICT (tenant_id) DO UPDATE
                   SET tenant_key = EXCLUDED.tenant_key,
                       tenant_name = EXCLUDED.tenant_name,
                       updated_at = now()
               RETURNING *""",
            (tenant_id, tenant_key, tenant_name),
        ).fetchone()


def set_chatwoot_account(tenant_id: str, account_id: int) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """UPDATE tenant_links SET chatwoot_account_id = %s, updated_at = now()
                WHERE tenant_id = %s RETURNING *""",
            (account_id, tenant_id),
        ).fetchone()


def get_tenant_link(tenant_id: str) -> dict | None:
    with get_connection() as conn:
        return conn.execute(
            "SELECT * FROM tenant_links WHERE tenant_id = %s", (tenant_id,)
        ).fetchone()


def tenant_link_by_account(chatwoot_account_id: int) -> dict | None:
    """Resolve o tenant a partir da Account do Chatwoot -- direção inversa de
    `get_tenant_link`. É o que permite ao Rails do Chatwoot (que só conhece a
    própria `Current.account.id`, autenticada pela sessão) provisionar
    recursos privilegiados (Evolution QR) sem nunca precisar saber ou
    declarar um `tenant_id`: a ponte é a única fonte de verdade desse
    vínculo, então não existe como um tenant forjar o id de outro."""
    with get_connection() as conn:
        return conn.execute(
            "SELECT * FROM tenant_links WHERE chatwoot_account_id = %s",
            (chatwoot_account_id,),
        ).fetchone()


def upsert_user_link(
    *, tenant_id: str, platform_user_id: str, email: str, role: str = "agent"
) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """INSERT INTO user_links (tenant_id, platform_user_id, email, role)
               VALUES (%s, %s, %s, %s)
               ON CONFLICT (tenant_id, platform_user_id) DO UPDATE
                   SET email = EXCLUDED.email, role = EXCLUDED.role, updated_at = now()
               RETURNING *""",
            (tenant_id, platform_user_id, email, role),
        ).fetchone()


def set_chatwoot_user(link_id: str, chatwoot_user_id: int) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """UPDATE user_links SET chatwoot_user_id = %s, updated_at = now()
                WHERE id = %s RETURNING *""",
            (chatwoot_user_id, link_id),
        ).fetchone()


def get_user_link(tenant_id: str, platform_user_id: str) -> dict | None:
    with get_connection() as conn:
        return conn.execute(
            "SELECT * FROM user_links WHERE tenant_id = %s AND platform_user_id = %s",
            (tenant_id, platform_user_id),
        ).fetchone()


def upsert_ai_config(
    *,
    tenant_id: str,
    chatwoot_inbox_id: int | None,
    template_id: str | None,
    integration_key: str | None,
    autopilot: bool = True,
    handoff_team_id: int | None = None,
) -> dict:
    with get_connection() as conn:
        # Caixa nova configurada pela tela não traz chave de integração: quem
        # escolhe o template na UI não deveria precisar saber que existe uma.
        # Herdar a chave que o tenant já usa é o que faz a IA responder ali;
        # sem isso a caixa fica configurada e muda.
        if not integration_key:
            herdada = conn.execute(
                """SELECT integration_key_encrypted FROM tenant_ai_config
                    WHERE tenant_id = %s AND integration_key_encrypted IS NOT NULL
                    ORDER BY (chatwoot_inbox_id IS NULL) DESC, updated_at DESC
                    LIMIT 1""",
                (tenant_id,),
            ).fetchone()
            if herdada:
                integration_key = decrypt(herdada["integration_key_encrypted"])
        return conn.execute(
            """INSERT INTO tenant_ai_config (tenant_id, chatwoot_inbox_id, template_id,
                                             integration_key_encrypted, autopilot, handoff_team_id)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON CONFLICT (tenant_id, chatwoot_inbox_id) DO UPDATE
                   SET template_id = EXCLUDED.template_id,
                       integration_key_encrypted = COALESCE(
                           EXCLUDED.integration_key_encrypted,
                           tenant_ai_config.integration_key_encrypted),
                       autopilot = EXCLUDED.autopilot,
                       handoff_team_id = EXCLUDED.handoff_team_id,
                       updated_at = now()
               RETURNING *""",
            (
                tenant_id,
                chatwoot_inbox_id,
                template_id,
                encrypt(integration_key) if integration_key else None,
                autopilot,
                handoff_team_id,
            ),
        ).fetchone()


def ai_config_for(tenant_id: str, inbox_id: int | None) -> dict | None:
    """Config do inbox, com queda para a config geral do tenant."""
    with get_connection() as conn:
        row = None
        if inbox_id is not None:
            row = conn.execute(
                """SELECT * FROM tenant_ai_config
                    WHERE tenant_id = %s AND chatwoot_inbox_id = %s""",
                (tenant_id, inbox_id),
            ).fetchone()
        if row is None:
            row = conn.execute(
                """SELECT * FROM tenant_ai_config
                    WHERE tenant_id = %s AND chatwoot_inbox_id IS NULL""",
                (tenant_id,),
            ).fetchone()
    return row


def set_default_teams(tenant_id: str, *, ai_team_id: int, handoff_team_id: int) -> dict:
    """Preenche a config padrão do tenant (chatwoot_inbox_id IS NULL) com os
    dois Teams criados no provisionamento — "Fila IA" e "Fila Humano".

    UPDATE explícito, não `INSERT ... ON CONFLICT (tenant_id, chatwoot_inbox_id)`:
    a UNIQUE constraint dessa tabela não trata dois NULLs como duplicata (regra
    do SQL), então um ON CONFLICT aqui criaria uma linha nova de config padrão
    a cada chamada em vez de atualizar a existente — bug fácil de não notar
    porque `ai_config_for` some sem erro nenhum, só passa a devolver a
    linha errada.

    COALESCE preserva um valor manual já configurado (ex.: alguém trocou o
    `handoff_team_id` pela tela antes deste provisionamento retroativo rodar).
    """
    with get_connection() as conn:
        updated = conn.execute(
            """UPDATE tenant_ai_config
                  SET ai_team_id = COALESCE(ai_team_id, %s),
                      handoff_team_id = COALESCE(handoff_team_id, %s),
                      updated_at = now()
                WHERE tenant_id = %s AND chatwoot_inbox_id IS NULL
                RETURNING *""",
            (ai_team_id, handoff_team_id, tenant_id),
        ).fetchone()
        if updated:
            return updated
        return conn.execute(
            """INSERT INTO tenant_ai_config (tenant_id, chatwoot_inbox_id,
                                             ai_team_id, handoff_team_id)
               VALUES (%s, NULL, %s, %s)
               RETURNING *""",
            (tenant_id, ai_team_id, handoff_team_id),
        ).fetchone()


def conversation_state(tenant_id: str, conversation_id: int) -> dict | None:
    with get_connection() as conn:
        return conn.execute(
            """SELECT * FROM conversation_states
                WHERE tenant_id = %s AND chatwoot_conversation_id = %s""",
            (tenant_id, conversation_id),
        ).fetchone()


def set_conversation_state(
    *,
    tenant_id: str,
    conversation_id: int,
    state: str,
    contact_identifier: str = "",
    session_id: str = "",
    last_error: str = "",
) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """INSERT INTO conversation_states (tenant_id, chatwoot_conversation_id, state,
                                                contact_identifier, session_id, last_error)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON CONFLICT (tenant_id, chatwoot_conversation_id) DO UPDATE
                   SET state = EXCLUDED.state,
                       contact_identifier = COALESCE(
                           NULLIF(EXCLUDED.contact_identifier, ''),
                           conversation_states.contact_identifier),
                       session_id = COALESCE(
                           NULLIF(EXCLUDED.session_id, ''), conversation_states.session_id),
                       last_error = EXCLUDED.last_error,
                       updated_at = now()
               RETURNING *""",
            (tenant_id, conversation_id, state, contact_identifier, session_id, last_error),
        ).fetchone()


def new_session_id() -> str:
    return secrets.token_urlsafe(12)


def set_agent_bot_id(tenant_id: str, bot_id: int) -> None:
    with get_connection() as conn:
        conn.execute(
            "UPDATE tenant_links SET chatwoot_agent_bot_id = %s WHERE tenant_id = %s",
            (bot_id, tenant_id),
        )


def ensure_conversation_webhook_token(tenant_id: str) -> str:
    """Token opaco da URL do Webhook de CONTA (label `ia-retomar`, macro
    "Devolver para IA"). Gerado uma vez e reaproveitado — o mesmo padrão de
    `tenant_channels.webhook_token`, aqui em `tenant_links` porque é por
    tenant, não por canal."""
    with get_connection() as conn:
        row = conn.execute(
            "SELECT conversation_webhook_token FROM tenant_links WHERE tenant_id = %s",
            (tenant_id,),
        ).fetchone()
        if row and row["conversation_webhook_token"]:
            return row["conversation_webhook_token"]
        token = secrets.token_hex(18)
        conn.execute(
            """UPDATE tenant_links SET conversation_webhook_token = %s, updated_at = now()
                WHERE tenant_id = %s""",
            (token, tenant_id),
        )
        return token


def tenant_by_conversation_webhook_token(token: str) -> dict | None:
    """Resolve o tenant pela URL do webhook de conta — o corpo do evento
    `conversation_updated` não traz account_id nem id global da conversa."""
    with get_connection() as conn:
        return conn.execute(
            "SELECT * FROM tenant_links WHERE conversation_webhook_token = %s", (token,)
        ).fetchone()


# --------------------------------------------------------------------------
# Evolution API por tenant (produto-05 seção 4) — QR automático, sem o
# administrador do tenant nunca digitar instance_name/api_url/api_key.
# --------------------------------------------------------------------------


def ensure_evolution_connection(
    *, tenant_id: str, indice: int, instance_name: str, api_url: str, api_key: str
) -> dict:
    """Cria a linha se não existir (gera o nome/URL/chave definitivos desta
    conexão UMA vez) ou devolve a existente sem tocar nela -- é isto que
    garante que repetir a chamada nunca gera um segundo container/instância
    para o mesmo (tenant_id, indice): quem decide se um provisionamento novo
    é necessário é sempre esta linha, nunca o chamador."""
    with get_connection() as conn:
        return conn.execute(
            """INSERT INTO evolution_connections
                   (tenant_id, indice, instance_name, api_url, api_key_encrypted, status)
               VALUES (%s, %s, %s, %s, %s, 'provisioning')
               ON CONFLICT (tenant_id, indice) DO UPDATE
                   SET updated_at = evolution_connections.updated_at
               RETURNING *""",
            (tenant_id, indice, instance_name, api_url, encrypt(api_key)),
        ).fetchone()


def ensure_evolution_db_passwords(connection_id: str) -> tuple[str, str]:
    """Devolve (pg_senha, redis_senha) desta conexão -- gera na primeira vez,
    sempre a MESMA depois. Achado real 24/08/2026 (produto-09): gerar senha
    nova a cada chamada de `provisionar_container`, mesmo quando o Postgres/
    Redis dependentes já existiam (sobreviventes de uma tentativa
    interrompida), deixava o container do Evolution com uma senha que não
    batia mais com a do banco -- crash-loop permanente. Ler daqui em vez de
    `secrets.token_urlsafe` direto é o que fecha esse buraco: a *linha* é a
    fonte de verdade da senha, não a chamada."""
    with get_connection() as conn:
        linha = conn.execute(
            """SELECT pg_password_encrypted, redis_password_encrypted
                 FROM evolution_connections WHERE id = %s""",
            (connection_id,),
        ).fetchone()
        if linha["pg_password_encrypted"] and linha["redis_password_encrypted"]:
            return (
                decrypt(linha["pg_password_encrypted"]),
                decrypt(linha["redis_password_encrypted"]),
            )

        pg_senha = secrets.token_urlsafe(24)
        redis_senha = secrets.token_urlsafe(24)
        conn.execute(
            """UPDATE evolution_connections
                  SET pg_password_encrypted = %s, redis_password_encrypted = %s, updated_at = now()
                WHERE id = %s""",
            (encrypt(pg_senha), encrypt(redis_senha), connection_id),
        )
        return pg_senha, redis_senha


def get_evolution_connection(tenant_id: str, indice: int = 1) -> dict | None:
    with get_connection() as conn:
        return conn.execute(
            "SELECT * FROM evolution_connections WHERE tenant_id = %s AND indice = %s",
            (tenant_id, indice),
        ).fetchone()


def mark_evolution_connection(
    connection_id: str, *, status: str, last_error: str = ""
) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """UPDATE evolution_connections
                  SET status = %s, last_error = %s, updated_at = now()
                WHERE id = %s
                RETURNING *""",
            (status, last_error, connection_id),
        ).fetchone()


# --------------------------------------------------------------------------
# Fila Demo IVR (produto-08) — menu numerado sem IA, isolado do fluxo acima.
# --------------------------------------------------------------------------


def menu_bot_config_for(tenant_id: str, inbox_id: int) -> dict | None:
    """Devolve a config da fila demo se esta inbox for uma delas — é essa
    checagem (feita ANTES de tocar em `conversation_state`/`ai_config_for")
    que garante o isolamento do fluxo de IA: nenhum outro código deste
    arquivo lê `menu_bot_config`, e esta função nunca é chamada pelo
    caminho de `_handle_message`."""
    with get_connection() as conn:
        return conn.execute(
            """SELECT * FROM menu_bot_config
                WHERE tenant_id = %s AND chatwoot_inbox_id = %s""",
            (tenant_id, inbox_id),
        ).fetchone()


def upsert_menu_bot_config(
    *,
    tenant_id: str,
    chatwoot_inbox_id: int,
    team_vendas_id: int | None = None,
    team_suporte_id: int | None = None,
    team_financeiro_id: int | None = None,
) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """INSERT INTO menu_bot_config (tenant_id, chatwoot_inbox_id,
                                            team_vendas_id, team_suporte_id, team_financeiro_id)
               VALUES (%s, %s, %s, %s, %s)
               ON CONFLICT (tenant_id, chatwoot_inbox_id) DO UPDATE
                   SET team_vendas_id = EXCLUDED.team_vendas_id,
                       team_suporte_id = EXCLUDED.team_suporte_id,
                       team_financeiro_id = EXCLUDED.team_financeiro_id,
                       updated_at = now()
               RETURNING *""",
            (tenant_id, chatwoot_inbox_id, team_vendas_id, team_suporte_id, team_financeiro_id),
        ).fetchone()


def menu_step_for(tenant_id: str, conversation_id: int) -> str:
    row = conversation_state(tenant_id, conversation_id)
    return (row or {}).get("menu_step") or ""


def set_menu_step(*, tenant_id: str, conversation_id: int, menu_step: str) -> dict:
    """UPSERT que toca só `menu_step` — nunca escreve em `state`/`session_id`,
    os campos do fluxo de IA, mesmo compartilhando a linha da tabela."""
    with get_connection() as conn:
        return conn.execute(
            """INSERT INTO conversation_states (tenant_id, chatwoot_conversation_id, menu_step)
               VALUES (%s, %s, %s)
               ON CONFLICT (tenant_id, chatwoot_conversation_id) DO UPDATE
                   SET menu_step = EXCLUDED.menu_step, updated_at = now()
               RETURNING *""",
            (tenant_id, conversation_id, menu_step),
        ).fetchone()
