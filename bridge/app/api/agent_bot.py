"""Agent Bot: o Chatwoot avisa, a IA responde ou entrega para um humano.

A máquina de estados vive aqui porque é ela que impede IA e atendente de
disputarem a mesma conversa:

    ai_active ──resposta──▶ ai_active
        │
        ├──handoff da IA──▶ human_queue ──▶ human_active ──▶ resolved
        └──humano escreve──▶ human_active   (a IA se cala sozinha)

Enquanto o estado não for `ai_active`, o bot não responde. Ponto.
"""

import logging

from fastapi import APIRouter, BackgroundTasks, Request

from app.services import chatwoot, kernel, tenants

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/agent-bot", tags=["agent-bot"])

AI_STATES = {"ai_active"}
HUMAN_STATES = {"human_queue", "human_active"}

# --------------------------------------------------------------------------
# Fila Demo IVR (produto-08): menu numerado "digite 1, digite 2", ZERO
# chamada ao kernel. Isolado de propósito: vive na mesma tabela de estado
# (`conversation_states.menu_step`) mas nunca lê/escreve `state`/`session_id`,
# e o branch em `agent_bot_webhook` decide ANTES de chegar em `_handle_message`
# — uma inbox nunca aciona os dois caminhos.
# --------------------------------------------------------------------------

MENU_WELCOME = (
    "Bem-vindo! Escolha uma opção:\n"
    "1 - Falar com vendas\n"
    "2 - Suporte técnico\n"
    "3 - Financeiro\n"
    "0 - Encerrar"
)

MENU_FALLBACK = "Não entendi, digite 1, 2, 3 ou 0."
MENU_GOODBYE = "Atendimento encerrado. Obrigado pelo contato!"
MENU_VOLTAR = "Digite 0 para voltar ao menu."

# opção -> (texto de resposta, campo da config com o Team a atribuir)
MENU_OPTIONS = {
    "1": (
        "Você escolheu Falar com vendas. Um especialista vai te atender em breve. "
        + MENU_VOLTAR,
        "team_vendas_id",
    ),
    "2": (
        "Você escolheu Suporte técnico. Nossa equipe já foi acionada. " + MENU_VOLTAR,
        "team_suporte_id",
    ),
    "3": (
        "Você escolheu Financeiro. Vamos te ajudar com sua questão financeira. " + MENU_VOLTAR,
        "team_financeiro_id",
    ),
}


async def _handle_menu_bot(
    tenant_id: str, account_id: int, conversation_id: int, content: str, menu_config: dict
) -> None:
    """Fluxo síncrono e sem estado de IA nenhum: só lê/escreve `menu_step`."""
    admin = _account_admin(tenant_id)
    if admin is None:
        return
    token = await chatwoot.user_access_token(int(admin["chatwoot_user_id"]))

    step = tenants.menu_step_for(tenant_id, conversation_id)

    if not step:
        # Primeira mensagem desta conversa na fila demo: manda o menu.
        await chatwoot.create_message(
            account_id, token, conversation_id, MENU_WELCOME, message_type="outgoing"
        )
        tenants.set_menu_step(
            tenant_id=tenant_id, conversation_id=conversation_id, menu_step="root"
        )
        return

    if step == "root":
        if content == "0":
            await chatwoot.create_message(
                account_id, token, conversation_id, MENU_GOODBYE, message_type="outgoing"
            )
            try:
                await chatwoot.toggle_status(account_id, token, conversation_id, "resolved")
            except chatwoot.ChatwootError as exc:
                logger.warning(
                    "falha ao encerrar conversa %s da fila demo: %s", conversation_id, exc
                )
            tenants.set_menu_step(
                tenant_id=tenant_id, conversation_id=conversation_id, menu_step="root"
            )
            return

        opcao = MENU_OPTIONS.get(content)
        if opcao is None:
            await chatwoot.create_message(
                account_id, token, conversation_id, MENU_FALLBACK, message_type="outgoing"
            )
            return

        reply, team_field = opcao
        await chatwoot.create_message(
            account_id, token, conversation_id, reply, message_type="outgoing"
        )
        team_id = (menu_config or {}).get(team_field)
        if team_id:
            try:
                await chatwoot.assign_team(account_id, token, conversation_id, int(team_id))
            except chatwoot.ChatwootError as exc:
                logger.warning(
                    "falha ao atribuir o Team da opção %s na conversa %s: %s",
                    content, conversation_id, exc,
                )
        tenants.set_menu_step(
            tenant_id=tenant_id, conversation_id=conversation_id, menu_step=f"option:{content}"
        )
        return

    # step == "option:<n>": só aceita "0" (volta ao menu); qualquer outra
    # coisa reforça a instrução, sem travar nem ignorar a conversa.
    if content == "0":
        await chatwoot.create_message(
            account_id, token, conversation_id, MENU_WELCOME, message_type="outgoing"
        )
        tenants.set_menu_step(
            tenant_id=tenant_id, conversation_id=conversation_id, menu_step="root"
        )
        return
    await chatwoot.create_message(
        account_id, token, conversation_id, MENU_VOLTAR, message_type="outgoing"
    )


async def _handle_message(tenant_id: str, account_id: int, payload: dict) -> None:
    conversation = payload.get("conversation") or {}
    conversation_id = int(conversation.get("id") or payload.get("conversation_id") or 0)
    if not conversation_id:
        return

    inbox_id = (conversation.get("inbox_id") or (payload.get("inbox") or {}).get("id"))
    content = (payload.get("content") or "").strip()
    if not content:
        return

    state_row = tenants.conversation_state(tenant_id, conversation_id)
    state = state_row["state"] if state_row else "ai_active"
    if state not in AI_STATES:
        # Humano no comando: a IA não fala por cima.
        return

    config = tenants.ai_config_for(tenant_id, int(inbox_id) if inbox_id else None)
    if config is None or not config["autopilot"]:
        return

    from app.crypto import decrypt

    session_id = (state_row or {}).get("session_id") or tenants.new_session_id()
    try:
        result = await kernel.ask(
            integration_key=decrypt(config["integration_key_encrypted"]),
            message=content,
            session_id=f"cw-{conversation_id}-{session_id}",
            template_id=str(config["template_id"]) if config["template_id"] else None,
        )
    except kernel.KernelError as exc:
        logger.warning("kernel indisponível para a conversa %s: %s", conversation_id, exc)
        tenants.set_conversation_state(
            tenant_id=tenant_id,
            conversation_id=conversation_id,
            state="human_queue",
            session_id=session_id,
            last_error=str(exc),
        )
        await _escalate(tenant_id, account_id, conversation_id, config, note=(
            "A IA não conseguiu responder agora (kernel indisponível). "
            "A conversa foi encaminhada para atendimento humano."
        ))
        return

    admin = _account_admin(tenant_id)
    if admin is None:
        return
    token = await chatwoot.user_access_token(int(admin["chatwoot_user_id"]))

    if result["reply"]:
        await chatwoot.create_message(
            account_id, token, conversation_id, result["reply"], message_type="outgoing"
        )

    if result["handoff"]:
        tenants.set_conversation_state(
            tenant_id=tenant_id,
            conversation_id=conversation_id,
            state="human_queue",
            session_id=session_id,
        )
        await _escalate(
            tenant_id, account_id, conversation_id, config,
            note="A IA pediu transferência para um atendente humano.",
            token=token,
        )
    else:
        tenants.set_conversation_state(
            tenant_id=tenant_id,
            conversation_id=conversation_id,
            state="ai_active",
            session_id=session_id,
        )
        # Atribui a conversa à "Fila IA" só na primeira mensagem (state_row
        # ainda não existia): a partir daí ela já fica no Team enquanto
        # continuar em ai_active, e chamar de novo a cada resposta seria 1
        # request HTTP a mais por mensagem sem necessidade nenhuma — o
        # Chatwoot não muda nada se o Team já é o mesmo, mas o custo é
        # nosso. Quando a Seção 2 desta spec (macro "Devolver para IA")
        # entrar, o retorno human_active -> ai_active precisa reatribuir de
        # novo; este `if` deixa de bastar sozinho e passa a precisar também
        # cobrir esse caminho (ex.: um "veio_de_handoff" explícito).
        ai_team_id = (config or {}).get("ai_team_id")
        if ai_team_id and state_row is None:
            try:
                await chatwoot.assign_team(
                    account_id, token, conversation_id, int(ai_team_id)
                )
            except chatwoot.ChatwootError as exc:
                logger.warning(
                    "falha ao atribuir a Fila IA na conversa %s: %s", conversation_id, exc
                )


async def _escalate(
    tenant_id: str,
    account_id: int,
    conversation_id: int,
    config: dict,
    *,
    note: str,
    token: str | None = None,
) -> None:
    """Handoff estruturado: nota privada + fila do time, não só um texto solto."""
    try:
        if token is None:
            admin = _account_admin(tenant_id)
            if admin is None:
                return
            token = await chatwoot.user_access_token(int(admin["chatwoot_user_id"]))
        await chatwoot.create_message(
            account_id, token, conversation_id, note, message_type="outgoing", private=True
        )
        if config.get("handoff_team_id"):
            await chatwoot.assign_team(
                account_id, token, conversation_id, int(config["handoff_team_id"])
            )
    except chatwoot.ChatwootError as exc:
        logger.warning("falha ao escalar conversa %s: %s", conversation_id, exc)


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


def _tenant_by_account(account_id: int) -> dict | None:
    from app.db import get_connection

    with get_connection() as conn:
        return conn.execute(
            "SELECT * FROM tenant_links WHERE chatwoot_account_id = %s", (account_id,)
        ).fetchone()


@router.post("")
async def agent_bot_webhook(request: Request, background: BackgroundTasks):
    """Recebe os eventos do Agent Bot. Sempre 200, processamento em background."""
    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        return {"status": "ignored"}

    account_id = payload.get("account", {}).get("id") or payload.get("account_id")
    if not account_id:
        return {"status": "ignored"}
    link = _tenant_by_account(int(account_id))
    if link is None:
        return {"status": "unknown_account"}
    tenant_id = str(link["tenant_id"])

    event = payload.get("event")
    if event != "message_created":
        return {"status": "ignored"}

    message_type = payload.get("message_type")
    conversation = payload.get("conversation") or {}
    conversation_id = int(conversation.get("id") or 0)

    # Mensagem de um atendente humano tira a IA do comando na hora.
    if message_type == "outgoing" and not payload.get("private"):
        sender_type = (payload.get("sender") or {}).get("type", "")
        if sender_type == "user" and conversation_id:
            tenants.set_conversation_state(
                tenant_id=tenant_id, conversation_id=conversation_id, state="human_active"
            )
        return {"status": "ok"}

    if message_type != "incoming":
        return {"status": "ignored"}

    # Branch da fila demo ANTES de qualquer coisa relacionada ao kernel — a
    # inbox nunca cai em `_handle_message` (custo zero de LLM garantido pela
    # própria topologia do código, não por uma flag em runtime).
    inbox_id = (conversation.get("inbox_id") or (payload.get("inbox") or {}).get("id"))
    if inbox_id:
        menu_config = tenants.menu_bot_config_for(tenant_id, int(inbox_id))
        if menu_config is not None:
            content = (payload.get("content") or "").strip()
            if content and conversation_id:
                background.add_task(
                    _handle_menu_bot,
                    tenant_id,
                    int(account_id),
                    conversation_id,
                    content,
                    menu_config,
                )
            return {"status": "accepted"}

    background.add_task(_handle_message, tenant_id, int(account_id), payload)
    return {"status": "accepted"}
