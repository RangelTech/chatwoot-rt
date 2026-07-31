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


def upsert_channel(
    *,
    tenant_id: str,
    provider: str,
    external_id: str,
    credentials: dict | None,
    api_base: str,
) -> dict:
    import json

    payload = encrypt(json.dumps(credentials)) if credentials else None
    with get_connection() as conn:
        existing = conn.execute(
            "SELECT * FROM tenant_channels WHERE provider = %s AND external_id = %s",
            (provider, external_id),
        ).fetchone()
        if existing and str(existing["tenant_id"]) != str(tenant_id):
            # Um mesmo canal não pode servir dois tenants: seria vazamento.
            raise PermissionError("canal já pertence a outro tenant")
        return conn.execute(
            """INSERT INTO tenant_channels (tenant_id, provider, external_id,
                                            credentials_encrypted, api_base)
               VALUES (%s, %s, %s, %s, %s)
               ON CONFLICT (provider, external_id) DO UPDATE
                   SET credentials_encrypted = COALESCE(
                           EXCLUDED.credentials_encrypted, tenant_channels.credentials_encrypted),
                       api_base = EXCLUDED.api_base,
                       updated_at = now()
               RETURNING *""",
            (tenant_id, provider, external_id, payload, api_base),
        ).fetchone()


def set_channel_inbox(channel_id: str, inbox_id: int, identifier: str | None) -> dict:
    with get_connection() as conn:
        return conn.execute(
            """UPDATE tenant_channels
                  SET chatwoot_inbox_id = %s, chatwoot_inbox_identifier = %s, updated_at = now()
                WHERE id = %s RETURNING *""",
            (inbox_id, identifier, channel_id),
        ).fetchone()


def channel_by_webhook_token(token: str) -> dict | None:
    """Resolve o tenant pela própria URL, antes de olhar o corpo do webhook."""
    with get_connection() as conn:
        return conn.execute(
            """SELECT c.*, t.chatwoot_account_id
                 FROM tenant_channels c
                 JOIN tenant_links t ON t.tenant_id = c.tenant_id
                WHERE c.webhook_token = %s AND c.is_active""",
            (token,),
        ).fetchone()


def channel_credentials(channel: dict) -> dict:
    import json

    raw = decrypt(channel.get("credentials_encrypted"))
    return json.loads(raw) if raw else {}


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
