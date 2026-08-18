"""Cliente do Chatwoot: Platform API (provisioning + SSO) e Application API.

A Platform API é privilegiada — cria contas e usuários e gera link de login.
A Application API opera dentro de uma conta com o token de um usuário/bot.
As duas ficam aqui para que nenhum outro módulo precise conhecer os detalhes
de rota ou de cabeçalho do Chatwoot.
"""

import asyncio
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
    # Uma segunda tentativa cobre o reset de conexão de quando o Cloud Run
    # troca de instância; erro de aplicação (4xx/5xx) não é repetido.
    ultimo: Exception | None = None
    response = None
    for tentativa in range(2):
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                response = await client.request(
                    method, url, headers={"api_access_token": token}, json=json_body, params=params
                )
            break
        except httpx.HTTPError as exc:
            ultimo = exc
            if tentativa == 0:
                await asyncio.sleep(2)
    if response is None:
        raise ChatwootError(f"Chatwoot inacessível: {ultimo}") from ultimo
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


async def create_team(account_id: int, token: str, name: str) -> dict:
    """Team da conta (Application API — precisa de token de usuário da conta,
    não do token de plataforma: Teams não existem na Platform API)."""
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/teams",
        token=token,
        json_body={"name": name},
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


async def create_account_webhook(
    account_id: int, token: str, url: str, subscriptions: list[str]
) -> dict:
    """Webhook de CONTA (Settings > Integrations > Webhooks) — mecanismo
    SEPARADO do Agent Bot webhook. É por aqui que a ponte escuta eventos que
    o Agent Bot não carrega, como `conversation_updated` (mudança de label ou
    de Team)."""
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/webhooks",
        token=token,
        json_body={"webhook": {"url": url, "subscriptions": subscriptions}},
    )


async def list_account_webhooks(account_id: int, token: str) -> list[dict]:
    body = await _request("GET", f"/api/v1/accounts/{account_id}/webhooks", token=token)
    payload = body.get("payload", body) if isinstance(body, dict) else body
    return payload or []


async def get_conversation(account_id: int, token: str, conversation_id: int) -> dict:
    """Busca a conversa pelo id usado nas rotas da Application API
    (o mesmo `display_id` que aparece na URL do Chatwoot). O corpo devolvido
    traz o `id` global da conversa — é a ponte entre os dois espaços de id
    quando só se tem o display_id (caso do webhook de conta, ver
    `label_webhook.py`)."""
    return await _request(
        "GET", f"/api/v1/accounts/{account_id}/conversations/{conversation_id}", token=token
    )


async def set_conversation_labels(
    account_id: int, token: str, conversation_id: int, labels: list[str]
) -> dict:
    """Substitui a lista inteira de labels — o Chatwoot não tem endpoint de
    remover UMA label, só de definir o conjunto todo."""
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/labels",
        token=token,
        json_body={"labels": labels},
    )


async def get_conversation_labels(account_id: int, token: str, conversation_id: int) -> list[str]:
    body = await _request(
        "GET", f"/api/v1/accounts/{account_id}/conversations/{conversation_id}/labels", token=token
    )
    payload = body.get("payload", body) if isinstance(body, dict) else body
    return payload or []


async def list_macros(account_id: int, token: str) -> list[dict]:
    body = await _request("GET", f"/api/v1/accounts/{account_id}/macros", token=token)
    payload = body.get("payload", body) if isinstance(body, dict) else body
    return payload or []


async def create_macro(
    account_id: int, token: str, name: str, actions: list[dict], visibility: str = "global"
) -> dict:
    """Macro nativa do Chatwoot (`Api::V1::Accounts::MacrosController`) — o
    "botão" que o atendente aperta. `actions` segue o formato interno do
    Chatwoot: [{"action_name": "add_label", "action_params": [...]}, ...]."""
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/macros",
        token=token,
        json_body={"name": name, "visibility": visibility, "actions": actions},
    )


async def list_inboxes(account_id: int, token: str) -> list[dict]:
    """Caixas de atendimento da conta, como o Chatwoot as conhece.

    A ponte guarda só as caixas que ela mesma criou (`tenant_channels`). Quem
    conecta um Instagram ou um site pelo próprio Chatwoot cria caixa que a ponte
    nunca viu — e é justamente nessas que alguém vai querer ligar a IA. Listar
    do Chatwoot é a única leitura que enxerga as duas origens.
    """
    body = await _request("GET", f"/api/v1/accounts/{account_id}/inboxes", token=token)
    caixas = body.get("payload", body) if isinstance(body, dict) else body
    return caixas or []


async def create_agent_bot(account_id: int, name: str, outgoing_url: str) -> dict:
    """Cria o Agent Bot da conta (Platform API)."""
    return await _request(
        "POST",
        "/platform/api/v1/agent_bots",
        token=_platform_token(),
        json_body={"name": name, "outgoing_url": outgoing_url, "account_id": account_id},
    )


async def set_agent_bot(account_id: int, token: str, inbox_id: int, bot_id: int | None) -> dict:
    """Liga (ou desliga, com None) o bot numa caixa.

    Sem isto o Chatwoot não avisa a ponte quando chega mensagem naquela caixa —
    e o sintoma é o pior tipo: template escolhido na tela, cliente escrevendo, e
    silêncio absoluto, sem erro em lugar nenhum.
    """
    return await _request(
        "POST",
        f"/api/v1/accounts/{account_id}/inboxes/{inbox_id}/set_agent_bot",
        token=token,
        json_body={"agent_bot": bot_id},
    )
