"""Cliente do agent-platform (kernel de IA).

A ponte não fala com o LangGraph direto: ela usa a API pública do
agent-platform (`POST /v1/messages`), que já resolve template ativo, modelo,
datasources, tools e memória. Assim a IA continua sendo domínio da plataforma
mestre, e a ponte só transporta contexto.
"""

import asyncio
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
    attachments: list[dict] | None = None,
) -> dict:
    """Manda a mensagem ao agente e devolve {reply, handoff, artifacts}.

    `attachments`: descritores no formato do `PublicAttachmentIn` do
    agent-platform (`{kind, name, content_type, data_base64}`) — hoje usado
    só para a nota de voz do Chatwoot (`kind="audio"`), transcrita do outro
    lado pelo mesmo pipeline que o chat web já usa (ver
    `_extract_audio_attachment`/`_handle_message` em `api/agent_bot.py`).
    """
    if not settings.agent_platform_url:
        raise KernelError("AGENT_PLATFORM_URL não configurado")
    if not integration_key:
        raise KernelError("tenant sem chave de integração com o agent-platform")

    body: dict = {"message": message, "external_session_id": session_id, "mode": "sync"}
    if template_id:
        body["template_id"] = template_id
    if attachments:
        body["attachments"] = attachments

    # Erro de transporte não é indisponibilidade: o Cloud Run recicla instância
    # o tempo todo e corta conexões em voo. Uma tentativa a mais evita mandar
    # a conversa para a fila humana por causa de um reset de conexão.
    ultimo: Exception | None = None
    response = None
    for tentativa in range(2):
        try:
            async with httpx.AsyncClient(timeout=TIMEOUT) as client:
                response = await client.post(
                    f"{settings.agent_platform_url.rstrip('/')}/v1/messages",
                    headers={"Authorization": f"Bearer {integration_key}"},
                    json=body,
                )
            break
        except httpx.HTTPError as exc:
            ultimo = exc
            if tentativa == 0:
                await asyncio.sleep(2)
    if response is None:
        raise KernelError(f"kernel inacessível: {ultimo}") from ultimo
    if response.status_code >= 400:
        raise KernelError(f"kernel respondeu {response.status_code}: {response.text[:400]}")

    payload = response.json()
    reply = (payload.get("reply") or "").strip()
    handoff = HANDOFF_MARKER in reply
    if handoff:
        reply = reply.replace(HANDOFF_MARKER, "").strip()
    return {"reply": reply, "handoff": handoff, "artifacts": payload.get("artifacts") or []}


async def fetch_artifact(*, integration_key: str, artifact_id: str) -> tuple[bytes, str, str]:
    """Downloads an artifact's bytes via the agent-platform's bearer-key
    endpoint (`GET /v1/artifacts/{id}`) — the same key used for `/v1/messages`,
    no user session needed. Returns (bytes, content_type, filename).

    This is what lets the bridge turn an `artifact` entry from `ask()` (kind
    "image", e.g. a chart PNG or the PIX QR code) into an actual file it can
    hand to Chatwoot's attachment upload.
    """
    if not settings.agent_platform_url:
        raise KernelError("AGENT_PLATFORM_URL não configurado")
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.get(
            f"{settings.agent_platform_url.rstrip('/')}/v1/artifacts/{artifact_id}",
            headers={"Authorization": f"Bearer {integration_key}"},
        )
    if response.status_code >= 400:
        raise KernelError(f"artifact {artifact_id}: {response.status_code} {response.text[:200]}")
    content_type = response.headers.get("content-type", "application/octet-stream")
    disposition = response.headers.get("content-disposition", "")
    filename = "artefato"
    if "filename=" in disposition:
        filename = disposition.split("filename=", 1)[1].strip('"; ')
    return response.content, content_type, filename
