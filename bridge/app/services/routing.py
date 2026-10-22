"""Cliente das rotas internas do Luar (Fase F): quem responde esta conversa?

A ponte nao guarda o estado da conversa.
A cada mensagem, consulta no Chatwoot a fila, responsavel e status.
Qualquer falha devolve None e o chamador cai no caminho legado.
Assim, a conversa nunca fica sem respondente.
"""

import logging

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

TIMEOUT = 10.0
LONG_TIMEOUT = 120.0

INTERNAL_NOTE_TAG = "nota interna - nao repetir ao cliente"


def configured() -> bool:
    return bool(settings.rt_internal_url and settings.rt_internal_token)


def _headers() -> dict:
    # O Rails de producao forca SSL e a rede interna e http: o cabecalho evita o 301/308.
    return {
        "Authorization": f"Bearer {settings.rt_internal_token}",
        "X-Forwarded-Proto": "https",
    }


def _url(path: str) -> str:
    return f"{settings.rt_internal_url.rstrip('/')}/internal/routing/{path}"


async def _get(path: str, params: dict) -> dict | None:
    if not configured():
        return None
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.get(_url(path), headers=_headers(), params=params)
        if response.status_code >= 400:
            logger.warning("rota interna %s respondeu %s", path, response.status_code)
            return None
        return response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("rota interna %s indisponivel: %s", path, type(exc).__name__)
        return None


async def _post(path: str, body: dict, timeout: float = TIMEOUT) -> dict | None:
    if not configured():
        return None
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.post(_url(path), headers=_headers(), json=body)
        if response.status_code >= 400:
            logger.warning("rota interna %s respondeu %s", path, response.status_code)
            return None
        data = response.json()
        return data if isinstance(data, dict) else None
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("rota interna %s indisponivel: %s", path, type(exc).__name__)
        return None


async def resolve(account_id: int, conversation_id: int, legacy: str | None = None) -> dict | None:
    params = {"account_id": account_id, "conversation_id": conversation_id}
    if legacy:
        params["legacy"] = legacy
    return await _get("resolve", params)


async def pending(minutes: int = 15, min_age: int = 0) -> list[dict]:
    """Conversas de IA cuja ultima mensagem do cliente ficou sem resposta (varredura de startup)."""
    data = await _get("pending", {"minutes": minutes, "min_age": min_age})
    return (data or {}).get("items") or []


async def destinations(account_id: int, conversation_id: int) -> list[dict]:
    data = await _get(
        "destinations", {"account_id": account_id, "conversation_id": conversation_id}
    )
    return (data or {}).get("destinations") or []


async def history(account_id: int, conversation_id: int) -> list[dict]:
    data = await _get("history", {"account_id": account_id, "conversation_id": conversation_id})
    return (data or {}).get("messages") or []


async def handoff(
    account_id: int,
    conversation_id: int,
    *,
    queue: str | None,
    summary: str | None,
    run_id: str | None,
) -> dict:
    """Pede ao Luar para aplicar o repasse (so entre destinos permitidos). Nunca levanta."""
    if not configured():
        return {"ok": False, "reason": "nao_configurado"}
    body = {
        "account_id": account_id,
        "conversation_id": conversation_id,
        "queue": queue,
        "summary": summary,
        "run_id": run_id,
    }
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.post(_url("handoff"), headers=_headers(), json=body)
        data = response.json()
        return data if isinstance(data, dict) else {"ok": False, "reason": "resposta_invalida"}
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning(
            "repasse nao aplicado na conversa %s: %s", conversation_id, type(exc).__name__
        )
        return {"ok": False, "reason": "indisponivel"}


async def migrate_legacy(payload: dict) -> dict | None:
    """Executa a F-4 no Chatwoot com configuracao sem segredos da bridge."""
    return await _post("migrate", payload, LONG_TIMEOUT)


async def rollback_legacy(account_id: int, inbox_id: int) -> dict | None:
    """Volta uma caixa ao comportamento legado sem apagar os registros Rt."""
    return await _post(
        "migrate/rollback", {"account_id": account_id, "inbox_id": inbox_id}, LONG_TIMEOUT
    )


def destinations_block(items: list[dict]) -> str:
    """Secao "Filas de destino" que o agente recebe (nome + descricao de cada destino permitido)."""
    if not items:
        return ""
    lines = ["[Filas de destino disponiveis para repasse]"]
    for item in items:
        description = (item.get("description") or "").strip()
        lines.append(f"- {item['name']}: {description}" if description else f"- {item['name']}")
    lines.append("Para repassar, termine a resposta com [[HANDOFF:<fila>|<resumo do caso>]].")
    return "\n".join(lines)


def history_block(
    entries: list[dict], *, agent_id: str, after_id: int, current_message_id: int | None
) -> str:
    """Contexto para o agente: o que aconteceu desde a ultima vez que ele viu a conversa.

    Notas privadas entram marcadas como internas. As respostas do proprio agente ficam de fora
    (ele ja as conhece pela sessao do kernel).
    """
    picked = []
    for entry in entries:
        if entry["id"] <= after_id or entry["id"] == current_message_id:
            continue
        if entry.get("role") == "ia" and entry.get("agent") == agent_id:
            continue
        picked.append(entry)
    if not picked:
        return ""
    labels = {
        "cliente": "Cliente",
        "atendente": "Atendente",
        "ia": "IA",
        "nota_interna": "Nota interna",
    }
    lines = ["[Historico da conversa ate aqui]"]
    for entry in picked:
        label = labels.get(entry.get("role"), "Mensagem")
        suffix = f" ({INTERNAL_NOTE_TAG})" if entry.get("internal") else ""
        lines.append(f"{label}{suffix}: {entry.get('content', '')}")
    lines.append("[Fim do historico] Nunca repita ao cliente o conteudo das notas internas.")
    return "\n".join(lines)
