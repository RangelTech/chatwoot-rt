"""Agent Bot: o Chatwoot avisa, a IA responde ou entrega para um humano.

A máquina de estados vive aqui porque é ela que impede IA e atendente de
disputarem a mesma conversa:

    ai_active ──resposta──▶ ai_active
        │
        ├──handoff da IA──▶ human_queue ──▶ human_active ──▶ resolved
        └──humano escreve──▶ human_active   (a IA se cala sozinha)

Enquanto o estado não for `ai_active`, o bot não responde. Ponto.
"""

import base64
import logging

from fastapi import APIRouter, BackgroundTasks, Request

from app.services import chatwoot, kernel, tenants

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/agent-bot", tags=["agent-bot"])

AI_STATES = {"ai_active"}
HUMAN_STATES = {"human_queue", "human_active"}

# --------------------------------------------------------------------------
# Áudio via Chatwoot (qa-02 seção 3b): antes desta ligação, uma nota de voz
# do WhatsApp/Instagram chegava com `content` vazio e o webhook devolvia
# cedo (`if not content: return`) — a IA nunca via nem o áudio nem qualquer
# outra coisa. `attachments` já vem no payload do `message_created`
# (sibling de `content`, não dentro de `conversation`); o Chatwoot já
# normaliza o `file_type` pra "audio" pra nota de voz de qualquer canal
# (WhatsApp, Instagram, etc.) — não precisa checar canal/inbox aqui.
# --------------------------------------------------------------------------

_AUDIO_FILE_TYPES = {"audio"}


def _extract_audio_attachment(payload: dict) -> dict | None:
    """Primeiro anexo de áudio do payload do webhook, ou None.

    Formato real do Chatwoot (`message_created`): `attachments: [{id,
    message_id, file_type, data_url, extension?}]`. `data_url` já é uma URL
    completa e assinada — não precisa de token de conta pra baixar (ver
    `chatwoot.download_attachment`).
    """
    for attachment in payload.get("attachments") or []:
        if attachment.get("file_type") in _AUDIO_FILE_TYPES and attachment.get("data_url"):
            return attachment
    return None


def _audio_filename(attachment: dict) -> str:
    """Nome de arquivo com a extensão certa — `transcribe()` (kernel-llm,
    `app/attachments.py`) manda esse nome pro `litellm.atranscription`, que
    usa a extensão pra saber o formato do áudio. WhatsApp manda Opus dentro
    de um container `.ogg`; o Chatwoot normalmente ecoa isso em `extension`
    ou no próprio `data_url`. Cai pra `.ogg` (o caso mais comum hoje) quando
    nenhum dos dois informa — nunca pra `.webm`, que é o formato do
    MediaRecorder do navegador (caminho 3a), não o do WhatsApp.
    """
    extension = (attachment.get("extension") or "").strip(".").lower()
    if not extension:
        data_url = attachment.get("data_url") or ""
        tail = data_url.rsplit("/", 1)[-1].rsplit("?", 1)[0]
        if "." in tail:
            extension = tail.rsplit(".", 1)[-1].lower()
    if not extension or len(extension) > 5:
        extension = "ogg"
    return f"nota-de-voz.{extension}"


_AUDIO_CONTENT_TYPES = {
    "ogg": "audio/ogg",
    "oga": "audio/ogg",
    "opus": "audio/ogg",
    "mp3": "audio/mpeg",
    "m4a": "audio/mp4",
    "mp4": "audio/mp4",
    "wav": "audio/wav",
    "webm": "audio/webm",
    "aac": "audio/aac",
}


async def _build_audio_attachment_payload(attachment: dict) -> dict | None:
    """Baixa o áudio do Chatwoot e monta o descritor que `PublicMessageIn`
    (agent-platform, `routes/public_api.py`) espera. None em caso de falha de
    download — o chamador decide o que fazer (não deixa a conversa travada)."""
    try:
        data = await chatwoot.download_attachment(attachment["data_url"])
    except chatwoot.ChatwootError as exc:
        logger.warning("falha ao baixar anexo de áudio do Chatwoot: %s", exc)
        return None
    if not data:
        return None
    filename = _audio_filename(attachment)
    extension = filename.rsplit(".", 1)[-1]
    content_type = _AUDIO_CONTENT_TYPES.get(extension, "audio/ogg")
    return {
        "kind": "audio",
        "name": filename,
        "content_type": content_type,
        "data_base64": base64.b64encode(data).decode(),
    }

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
    audio_attachment = _extract_audio_attachment(payload)
    # Antes desta ligação (qa-02 seção 3b), uma nota de voz sozinha (sem
    # legenda) tinha `content` vazio e caía aqui — a conversa nunca chegava a
    # sair do webhook. Só segue sem conteúdo se houver áudio pra transcrever.
    if not content and audio_attachment is None:
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

    kernel_attachments: list[dict] = []
    if audio_attachment is not None:
        built = await _build_audio_attachment_payload(audio_attachment)
        if built is not None:
            kernel_attachments.append(built)
        elif not content:
            # Download falhou e não sobrou nem texto: melhor um placeholder
            # explícito pra IA reagir a isso do que mandar mensagem vazia
            # (o backend rejeitaria) ou fingir silêncio.
            content = "(o cliente enviou um áudio, mas não foi possível baixá-lo)"

    session_id = (state_row or {}).get("session_id") or tenants.new_session_id()
    try:
        result = await kernel.ask(
            integration_key=decrypt(config["integration_key_encrypted"]),
            message=content or "(áudio recebido)",
            session_id=f"cw-{conversation_id}-{session_id}",
            template_id=str(config["template_id"]) if config["template_id"] else None,
            attachments=kernel_attachments or None,
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

    await _deliver_artifacts(
        tenant_id=tenant_id,
        account_id=account_id,
        token=token,
        conversation_id=conversation_id,
        integration_key=decrypt(config["integration_key_encrypted"]),
        artifacts=result.get("artifacts") or [],
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


async def _deliver_artifacts(
    *,
    tenant_id: str,
    account_id: int,
    token: str,
    conversation_id: int,
    integration_key: str,
    artifacts: list[dict],
) -> None:
    """Renders artifacts the kernel produced this turn (chart PNGs, the PIX
    QR code) as real Chatwoot attachments.

    Before this existed, an "image" artifact from `generate_pix_charge` or
    `generate_chart` had no delivery path here at all: `/v1/messages` (the
    endpoint this bridge calls) never surfaced artifact events, and even if
    it had, `chatwoot.create_message` only knows how to send a JSON body with
    `content` — no attachment field. A WhatsApp customer asking for a PIX
    charge got the copy-paste code as text (that part rides in `reply`) but
    never the QR code image; a chart request either got nothing extra or,
    depending on the model's phrasing, a claim of showing an image that never
    arrived. This closes that gap for every "image" artifact, not just PIX.

    Non-image kinds (e.g. "file") are left alone for now — those already have
    a working delivery story via the signed download link that rides in the
    reply text (see qa-02 seção 4); only "image" had no fallback at all.
    """
    for artifact in artifacts:
        if artifact.get("kind") != "image":
            continue
        try:
            data, content_type, filename = await kernel.fetch_artifact(
                integration_key=integration_key, artifact_id=artifact["artifact_id"]
            )
            await chatwoot.create_message_with_attachment(
                account_id,
                token,
                conversation_id,
                file_bytes=data,
                filename=filename,
                content_type=content_type,
                message_type="outgoing",
            )
        except (kernel.KernelError, chatwoot.ChatwootError) as exc:
            # Uma imagem que falha para entregar não pode derrubar o resto do
            # turno: o cliente já recebeu o texto (copia-e-cola do PIX, por
            # exemplo) — perder só a imagem é degradação aceitável, silêncio
            # total não é.
            logger.warning(
                "falha ao entregar artefato %s na conversa %s (tenant %s): %s",
                artifact.get("artifact_id"), conversation_id, tenant_id, exc,
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
