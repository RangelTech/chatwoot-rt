"""Cliente do Chatwoot: Platform API (provisioning + SSO) e Application API.

A Platform API é privilegiada — cria contas e usuários e gera link de login.
A Application API opera dentro de uma conta com o token de um usuário/bot.
As duas ficam aqui para que nenhum outro módulo precise conhecer os detalhes
de rota ou de cabeçalho do Chatwoot.
"""

import logging
from typing import Any

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

TIMEOUT = 30.0


class ChatwootError(RuntimeError):
    pass


async def _request(
    method: str,
    path: str,
    *,
    token: str,
    json_body: dict | None = None,
    params: dict | None = None,
) -> Any:
    url = f"{settings.chatwoot_base_url.rstrip('/')}{path}"
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.request(
                method, url, headers={"api_access_token": token}, json=json_body, params=params
            )
    except httpx.HTTPError as exc:
        raise ChatwootError(f"Chatwoot inacessível: {exc}") from exc
    if response.status_code >= 400:
        raise ChatwootError(f"Chatwoot respondeu {response.status_code}: {response.text[:400]}")
    if not response.content:
        return {}
    try:
        return response.json()
    except ValueError:
        return {"raw": response.text[:1000]}


def _platform_token() -> str:
    if not settings.chatwoot_platform_token:
        raise ChatwootError("CHATWOOT_PLATFORM_TOKEN não configurado")
    return settings.chatwoot_platform_token


# --------------------------------------------------------------------------
# Platform API — provisioning e SSO
# --------------------------------------------------------------------------


async def create_account(name: str) -> dict:
    return await _request(
        "POST", "/platform/api/v1/accounts", token=_platform_token(), json_body={"name": name}
    )


async def get_account(account_id: int) -> dict:
    return await _request(
        "GET", f"/platform/api/v1/accounts/{account_id}", token=_platform_token()
    )


async def create_user(name: str, email: str, password: str) -> dict:
    return await _request(
        "POST",
        "/platform/api/v1/users",
        token=_platform_token(),
        json_body={"name": name, "email": email, "password": password},
    )


async def add_account_user(account_id: int, user_id: int, role: str = "agent") -> dict:
    return await _request(
        "POST",
        f"/platform/api/v1/accounts/{account_id}/account_users",
        token=_platform_token(),
        json_body={"user_id": user_id, "role": role},
    )


async def login_link(user_id: int) -> str:
    """URL temporária de login — é isso que evita recadastro no Chatwoot."""
    body = await _request("GET", f"/platform/api/v1/users/{user_id}/login", token=_platform_token())
    url = body.get("url") if isinstance(body, dict) else None
    if not url:
        raise ChatwootError("Chatwoot não devolveu URL de login")
    return url


async def user_access_token(user_id: int) -> str:
    body = await _request("GET", f"/platform/api/v1/users/{user_id}", token=_platform_token())
    token = (body or {}).get("access_token")
    if not token:
        raise ChatwootError("Chatwoot não devolveu access_token do usuário")
    return token


# --------------------------------------------------------------------------
# Application API — operação dentro de uma conta
# --------------------------------------------------------------------------


async def create_api_inbox(account_id: int, token: str, name: str, webhook_url: str) -> dict:
    """Inbox do tipo API: é por ela que o gateway injeta as mensagens."""
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/inboxes",
        token=token,
        json_body={
            "name": name,
            "channel": {"type": "api", "webhook_url": webhook_url},
        },
    )


async def create_contact(account_id: int, token: str, identifier: str, name: str) -> dict:
    body: dict = {"identifier": identifier, "name": name}
    # Só WhatsApp tem telefone. Instagram e Facebook usam id de perfil, e o
    # Chatwoot rejeita qualquer coisa que não seja E.164 nesse campo.
    if identifier.isdigit():
        body["phone_number"] = f"+{identifier}"
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/contacts",
        token=token,
        json_body=body,
    )


async def search_contact(account_id: int, token: str, identifier: str) -> dict | None:
    body = await _request(
        "GET",
        f"/api/v1/accounts/{account_id}/contacts/search",
        token=token,
        params={"q": identifier},
    )
    payload = (body or {}).get("payload") or []
    return payload[0] if payload else None


async def create_conversation(
    account_id: int, token: str, inbox_id: int, contact_id: int, source_id: str
) -> dict:
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/conversations",
        token=token,
        json_body={"inbox_id": inbox_id, "contact_id": contact_id, "source_id": source_id},
    )


async def create_message(
    account_id: int,
    token: str,
    conversation_id: int,
    content: str,
    *,
    message_type: str = "incoming",
    private: bool = False,
) -> dict:
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/messages",
        token=token,
        json_body={"content": content, "message_type": message_type, "private": private},
    )


async def assign_team(account_id: int, token: str, conversation_id: int, team_id: int) -> dict:
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/assignments",
        token=token,
        json_body={"team_id": team_id},
    )


async def toggle_status(account_id: int, token: str, conversation_id: int, status: str) -> dict:
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/toggle_status",
        token=token,
        json_body={"status": status},
    )
