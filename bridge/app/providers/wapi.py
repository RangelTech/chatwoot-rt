"""Provedor W-API (WhatsApp não-oficial).

A ponte fala com provedores por trás desta interface: `extract_message` traduz
o webhook do provedor para o evento canônico interno, e `send_text` entrega a
resposta. Trocar de provedor (Z-API, Meta Cloud) é escrever outro módulo com
estas duas funções, sem tocar no resto da ponte.
"""

import logging
from typing import Any

import httpx

logger = logging.getLogger(__name__)

NAME = "wapi"
TIMEOUT = 20.0


class ProviderError(RuntimeError):
    pass


def extract_message(payload: dict[str, Any]) -> dict | None:
    """Webhook do provedor -> evento canônico {contact, text, external_id}.

    Devolve None para o que não é mensagem de entrada com texto: status de
    entrega, confirmação de leitura e eco das mensagens que nós mesmos
    enviamos (senão o bot conversa sozinho).
    """
    if not isinstance(payload, dict):
        return None
    if payload.get("fromMe") or (payload.get("key") or {}).get("fromMe"):
        return None

    event = str(payload.get("event") or payload.get("type") or "").lower()
    if any(word in event for word in ("status", "ack", "read", "deliver", "receipt")):
        return None
    if event and "message" not in event and "chat" not in event:
        return None

    phone = (
        payload.get("phone")
        or payload.get("sender")
        or payload.get("from")
        or (payload.get("key") or {}).get("remoteJid")
        or ""
    )
    phone = str(phone).split("@")[0].strip()

    message = payload.get("message") if isinstance(payload.get("message"), dict) else {}
    raw_text = payload.get("text")
    if isinstance(raw_text, str):
        text = raw_text
    elif isinstance(raw_text, dict):
        text = raw_text.get("message")
    else:
        text = None
    text = (
        text
        or message.get("conversation")
        or (message.get("extendedTextMessage") or {}).get("text")
        or payload.get("body")
        or ""
    )
    text = str(text).strip()
    if not phone or not text:
        return None

    return {
        "provider": NAME,
        "contact": phone,
        "text": text[:32_000],
        "external_id": str(payload.get("messageId") or payload.get("id") or "") or None,
        "contact_name": str(payload.get("senderName") or payload.get("pushName") or "") or phone,
    }


async def send_text(credentials: dict, api_base: str, instance_id: str, to: str, text: str) -> dict:
    token = credentials.get("token")
    if not token:
        raise ProviderError("canal sem token configurado")
    url = f"{api_base.rstrip('/')}/message/send-text"
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.post(
                url,
                params={"instanceId": instance_id},
                headers={"Authorization": f"Bearer {token}"},
                json={"phone": to, "message": text},
            )
    except httpx.HTTPError as exc:
        raise ProviderError(f"provedor inacessível: {exc}") from exc
    if response.status_code >= 400:
        raise ProviderError(f"provedor respondeu {response.status_code}: {response.text[:300]}")
    try:
        return response.json()
    except ValueError:
        return {}


async def check_status(credentials: dict, api_base: str, instance_id: str) -> dict:
    token = credentials.get("token")
    if not token:
        raise ProviderError("canal sem token configurado")
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.get(
                f"{api_base.rstrip('/')}/instance/status",
                params={"instanceId": instance_id},
                headers={"Authorization": f"Bearer {token}"},
            )
    except httpx.HTTPError as exc:
        raise ProviderError(f"provedor inacessível: {exc}") from exc
    if response.status_code >= 400:
        raise ProviderError(f"provedor respondeu {response.status_code}: {response.text[:300]}")
    try:
        return response.json()
    except ValueError:
        return {}
