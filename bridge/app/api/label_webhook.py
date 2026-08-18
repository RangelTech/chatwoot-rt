"""Webhook de CONTA (Settings > Integrations > Webhooks) — evento
`conversation_updated`, usado só para o botão "Devolver para IA" (Macro que
aplica a label reservada `ia-retomar`, ver `admin._ensure_devolver_para_ia`).

Mecanismo SEPARADO do Agent Bot webhook (`agent_bot.py`): o Chatwoot dispara
`conversation_updated` tanto para mudança de label quanto de Team, mas o
corpo desse evento (`Conversations::EventDataPresenter#push_data`) não traz
`account_id` nem o id global da conversa — só `id` (na verdade o
`display_id`, sequencial POR CONTA, colide entre tenants) e `labels`. Por
isso o tenant é resolvido pela própria URL (token opaco), como no webhook do
WhatsApp não-oficial (`webhooks.py`).

Cuidado com o id: o `display_id` do payload NÃO é o id que o resto do bridge
usa como chave de `conversation_states` (esse vem do payload do Agent Bot, que
é o id global da conversa — `agent_bot.py:_handle_message`). Misturar os dois
faria `set_conversation_state` gravar sob uma chave que a IA nunca lê. Por
isso, antes de tocar no estado, este módulo busca a conversa pelo display_id
(`GET /conversations/{display_id}`, que é como a Application API resolve esse
parâmetro) e usa o `id` global devolvido no corpo.
"""

import logging

from fastapi import APIRouter, BackgroundTasks, Request

from app.api.admin import LABEL_DEVOLVER_IA
from app.services import chatwoot, tenants

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/agent-bot/label", tags=["agent-bot"])


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


async def _handle_label_event(tenant_id: str, account_id: int, display_id: int) -> None:
    admin = _account_admin(tenant_id)
    if admin is None:
        return
    token = await chatwoot.user_access_token(int(admin["chatwoot_user_id"]))

    try:
        # O payload só traz display_id; o estado da conversa é chaveado pelo
        # id global (o mesmo que o Agent Bot manda) — busca a conversa para
        # traduzir um para o outro.
        conversation = await chatwoot.get_conversation(account_id, token, display_id)
        conversation_id = int(conversation.get("id") or 0)
        if not conversation_id:
            return

        tenants.set_conversation_state(
            tenant_id=tenant_id, conversation_id=conversation_id, state="ai_active"
        )

        # Remove a label para poder ser reaplicada depois, se a conversa
        # escalar de novo. Best-effort: se falhar, a IA já voltou ao comando
        # (o que importa), só a limpeza da label fica pendente.
        try:
            labels = await chatwoot.get_conversation_labels(account_id, token, display_id)
            restantes = [label for label in labels if label != LABEL_DEVOLVER_IA]
            if len(restantes) != len(labels):
                await chatwoot.set_conversation_labels(account_id, token, display_id, restantes)
        except chatwoot.ChatwootError as exc:
            logger.warning(
                "conversa %s voltou para ai_active, mas não deu para remover a label '%s': %s",
                conversation_id,
                LABEL_DEVOLVER_IA,
                exc,
            )
    except chatwoot.ChatwootError as exc:
        logger.warning(
            "falha ao processar 'Devolver para IA' (display_id=%s) do tenant %s: %s",
            display_id,
            tenant_id,
            exc,
        )


@router.post("/{webhook_token}")
async def label_webhook(webhook_token: str, request: Request, background: BackgroundTasks):
    """Sempre 200 — 5xx aqui viraria reenvio em loop do lado do Chatwoot."""
    link = tenants.tenant_by_conversation_webhook_token(webhook_token)
    if link is None or not link["chatwoot_account_id"]:
        return {"status": "unknown_tenant"}

    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        return {"status": "ignored"}

    if payload.get("event") != "conversation_updated":
        return {"status": "ignored"}

    # `changed_attributes` só vem preenchido quando o campo mudou nesta
    # atualização; `labels` no corpo é sempre a lista atual (lista simples de
    # strings) — usamos a atual, que já reflete a label aplicada pela macro.
    labels = payload.get("labels") or []
    if LABEL_DEVOLVER_IA not in labels:
        return {"status": "ignored"}

    display_id = int(payload.get("id") or 0)
    if not display_id:
        return {"status": "ignored"}

    background.add_task(
        _handle_label_event, str(link["tenant_id"]), int(link["chatwoot_account_id"]), display_id
    )
    return {"status": "accepted"}
