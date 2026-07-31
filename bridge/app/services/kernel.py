"""Cliente do agent-platform (kernel de IA).

A ponte não fala com o LangGraph direto: ela usa a API pública do
agent-platform (`POST /v1/messages`), que já resolve template ativo, modelo,
datasources, tools e memória. Assim a IA continua sendo domínio da plataforma
mestre, e a ponte só transporta contexto.
"""

import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

TIMEOUT = 300.0

# Convenção de handoff: o agente termina a resposta com este marcador quando
# entende que um humano precisa assumir. Fica no protocolo, não no prompt de
# um tenant específico.
HANDOFF_MARKER = "[[HANDOFF]]"


class KernelError(RuntimeError):
    pass


async def ask(
    *,
    integration_key: str,
    message: str,
    session_id: str,
    template_id: str | None = None,
) -> dict:
    """Manda a mensagem ao agente e devolve {reply, handoff}."""
    if not settings.agent_platform_url:
        raise KernelError("AGENT_PLATFORM_URL não configurado")
    if not integration_key:
        raise KernelError("tenant sem chave de integração com o agent-platform")

    body: dict = {"message": message, "external_session_id": session_id, "mode": "sync"}
    if template_id:
        body["template_id"] = template_id

    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.post(
                f"{settings.agent_platform_url.rstrip('/')}/v1/messages",
                headers={"Authorization": f"Bearer {integration_key}"},
                json=body,
            )
    except httpx.HTTPError as exc:
        raise KernelError(f"kernel inacessível: {exc}") from exc
    if response.status_code >= 400:
        raise KernelError(f"kernel respondeu {response.status_code}: {response.text[:400]}")

    payload = response.json()
    reply = (payload.get("reply") or "").strip()
    handoff = HANDOFF_MARKER in reply
    if handoff:
        reply = reply.replace(HANDOFF_MARKER, "").strip()
    return {"reply": reply, "handoff": handoff}
