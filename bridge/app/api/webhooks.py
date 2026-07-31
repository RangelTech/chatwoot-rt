"""Entrada de canal: webhook do provedor -> Chatwoot.

Contrato desta rota:

1. o tenant é resolvido pela **URL** (token opaco), antes de olhar o corpo;
2. o corpo cru é gravado antes de qualquer parsing;
3. evento repetido é reconhecido pelo índice único e ignorado;
4. a resposta é sempre 200 — 5xx vira reenvio em loop do lado do provedor.
"""

import logging

from fastapi import APIRouter, BackgroundTasks, Request

from app.providers import wapi
from app.services import chatwoot, events, tenants

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["webhooks"])


async def _deliver_to_chatwoot(channel: dict, message: dict, event_id: str) -> None:
    """Injeta a mensagem na inbox de API do tenant, criando contato/conversa."""
    tenant_id = str(channel["tenant_id"])
    account_id = int(channel["chatwoot_account_id"])
    inbox_id = channel["chatwoot_inbox_id"]
    if not inbox_id:
        events.update_event(event_id, state="dead_letter", detail="canal sem inbox no Chatwoot")
        return

    try:
        admin = _account_admin(tenant_id)
        if admin is None:
            events.update_event(
                event_id, state="dead_letter", detail="tenant sem usuário administrador"
            )
            return
        token = await chatwoot.user_access_token(int(admin["chatwoot_user_id"]))

        contact = await chatwoot.search_contact(account_id, token, message["contact"])
        if contact is None:
            created = await chatwoot.create_contact(
                account_id,
                token,
                message["contact"],
                message.get("contact_name") or message["contact"],
            )
            contact = (created.get("payload") or {}).get("contact") or created
        contact_id = int(contact["id"])

        conversation = await chatwoot.create_conversation(
            account_id, token, int(inbox_id), contact_id, source_id=message["contact"]
        )
        conversation_id = int(conversation["id"])

        await chatwoot.create_message(
            account_id, token, conversation_id, message["text"], message_type="incoming"
        )
        state = tenants.conversation_state(tenant_id, conversation_id)
        tenants.set_conversation_state(
            tenant_id=tenant_id,
            conversation_id=conversation_id,
            state=state["state"] if state else "ai_active",
            contact_identifier=message["contact"],
            session_id=(state or {}).get("session_id") or tenants.new_session_id(),
        )
        events.update_event(event_id, state="persisted", detail=f"conversation={conversation_id}")
    except chatwoot.ChatwootError as exc:
        logger.warning("falha ao entregar no Chatwoot: %s", exc)
        events.update_event(event_id, state="retry_scheduled", detail=str(exc))
    except Exception as exc:  # noqa: BLE001 — webhook já respondeu 200
        logger.exception("erro inesperado ao entregar evento de canal")
        events.update_event(event_id, state="dead_letter", detail=str(exc))


def _account_admin(tenant_id: str) -> dict | None:
    from app.db import get_connection

    with get_connection() as conn:
        return conn.execute(
            """SELECT * FROM user_links
                WHERE tenant_id = %s AND chatwoot_user_id IS NOT NULL
                ORDER BY (role = 'administrator') DESC, created_at
                LIMIT 1""",
            (tenant_id,),
        ).fetchone()


@router.post("/wapi/{webhook_token}")
async def wapi_webhook(webhook_token: str, request: Request, background: BackgroundTasks):
    raw = (await request.body()).decode("utf-8", errors="replace")

    channel = tenants.channel_by_webhook_token(webhook_token)
    if channel is None:
        events.record_event(
            tenant_id=None,
            channel_id=None,
            provider=wapi.NAME,
            dedup_key=None,
            raw_body=raw,
            state="unknown_channel",
        )
        return {"status": "ignored"}

    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001 — corpo inválido não pode virar retry infinito
        events.record_event(
            tenant_id=str(channel["tenant_id"]),
            channel_id=str(channel["id"]),
            provider=wapi.NAME,
            dedup_key=None,
            raw_body=raw,
            state="unparseable",
        )
        return {"status": "ignored"}

    message = wapi.extract_message(payload)
    if message is None:
        events.record_event(
            tenant_id=str(channel["tenant_id"]),
            channel_id=str(channel["id"]),
            provider=wapi.NAME,
            dedup_key=None,
            raw_body=raw,
            state="no_content",
        )
        return {"status": "ignored"}

    event = events.record_event(
        tenant_id=str(channel["tenant_id"]),
        channel_id=str(channel["id"]),
        provider=wapi.NAME,
        dedup_key=message.get("external_id"),
        raw_body=raw,
        state="normalized",
    )
    if event is None:
        # Já processado numa entrega anterior do mesmo evento.
        return {"status": "duplicate_ignored"}

    background.add_task(_deliver_to_chatwoot, dict(channel), message, str(event["id"]))
    return {"status": "accepted"}
