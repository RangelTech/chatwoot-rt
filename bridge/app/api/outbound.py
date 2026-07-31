"""Saída: o que sai do Chatwoot volta para o canal do cliente.

A inbox de API do Chatwoot chama esta rota sempre que alguém responde — a IA
ou um atendente humano. A ponte pega essa mensagem e entrega no provedor.
Sem isso a conversa seria de mão única.
"""

import logging

from fastapi import APIRouter, BackgroundTasks, Request

from app.providers import wapi
from app.services import events, tenants

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/outbound", tags=["outbound"])


async def _send(channel: dict, to: str, text: str, event_id: str) -> None:
    credentials = tenants.channel_credentials(channel)
    try:
        await wapi.send_text(
            credentials, channel["api_base"], channel["external_id"], to=to, text=text
        )
        events.update_event(event_id, state="delivered")
    except wapi.ProviderError as exc:
        # Processado mas não entregue: fica registrado para reenvio.
        logger.warning("resposta não entregue no canal: %s", exc)
        events.update_event(event_id, state="provider_unavailable", detail=str(exc))


@router.post("/{webhook_token}")
async def outbound_webhook(webhook_token: str, request: Request, background: BackgroundTasks):
    raw = (await request.body()).decode("utf-8", errors="replace")

    channel = tenants.channel_by_webhook_token(webhook_token)
    if channel is None:
        return {"status": "ignored"}

    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        events.record_event(
            tenant_id=str(channel["tenant_id"]),
            channel_id=str(channel["id"]),
            provider=channel["provider"],
            dedup_key=None,
            raw_body=raw,
            state="unparseable",
            direction="out",
        )
        return {"status": "ignored"}

    # Só mensagens que saem para o cliente; nota privada fica no Chatwoot.
    if payload.get("message_type") not in ("outgoing", 1) or payload.get("private"):
        return {"status": "ignored"}

    content = (payload.get("content") or "").strip()
    conversation = payload.get("conversation") or {}
    contact = (
        (payload.get("conversation") or {}).get("meta", {}).get("sender", {}).get("identifier")
        or (payload.get("contact") or {}).get("identifier")
        or conversation.get("source_id")
    )
    if not content or not contact:
        return {"status": "ignored"}

    event = events.record_event(
        tenant_id=str(channel["tenant_id"]),
        channel_id=str(channel["id"]),
        provider=channel["provider"],
        dedup_key=f"out-{payload.get('id')}" if payload.get("id") else None,
        raw_body=raw,
        state="routed",
        direction="out",
    )
    if event is None:
        return {"status": "duplicate_ignored"}

    background.add_task(_send, dict(channel), str(contact), content, str(event["id"]))
    return {"status": "accepted"}
