"""Tipos compartilhados do gateway de canais (ver docs/canais/CONTRATO_GATEWAY.md)."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.channels.states import State

Provider = Literal["instagram", "messenger", "whatsapp", "tiktok"]
StepKind = Literal[
    "credentials",
    "code_2fa",
    "captcha",
    "choice",
    "await_approval",
    "qr",
    "pairing_code",
    "syncing",
    "complete",
]


class StepField(BaseModel):
    id: str
    type: Literal[
        "username",
        "password",
        "2fa_code",
        "text",
        "select",
        "captcha_code",
        "phone_number",
        "email",
    ]
    label_key: str
    secret: bool = False
    label: str = ""  # nome vindo do bridge (ingles); a tela prefere label_key quando traduzido
    options: list[str] = Field(default_factory=list)
    default: str | None = None


class StepAttachment(BaseModel):
    """Imagem/audio do passo (ex.: captcha). Nao e segredo: o proprio provedor o mostra."""

    kind: Literal["image", "audio"]
    mime: str = ""
    name: str = ""
    data: str  # base64


class QrInfo(BaseModel):
    data: str
    expires_at: datetime
    refresh_after_s: int = 20


class WaitInfo(BaseModel):
    poll_after_s: int = 2
    can_cancel: bool = True


class Step(BaseModel):
    step_id: str
    kind: StepKind
    instructions_key: str = ""
    instructions: str = ""  # texto do bridge (ingles), exibido como detalhe quando nao ha traducao
    attachments: list[StepAttachment] = Field(default_factory=list)
    fields: list[StepField] = Field(default_factory=list)
    qr: QrInfo | None = None
    pairing_code: str | None = None
    wait: WaitInfo | None = None
    error_code: str | None = None
    attempts_left: int | None = None


class StepView(BaseModel):
    state: State
    step: Step | None = None
    login_id: str | None = None  # id do login no bridge; interno, nunca exposto


class Health(BaseModel):
    process: bool = False  # processo/worker vivo
    session: bool = False  # sessão autenticada no provedor
    io: bool = False  # capaz de enviar/receber


class ConnectionCtx(BaseModel):
    """O que um adaptador precisa saber da conexão. Nunca carrega segredo."""

    id: str
    account_id: int
    provider: Provider
    matrix_user: str | None = None  # @luar_t<conta>_c<id>:<servidor>
    gateway_login_id: str | None = None
    external_label: str = ""


class Attachment(BaseModel):
    kind: Literal["image", "video", "audio", "file"]
    mime: str = ""
    name: str = ""
    url: str


class InboundMessage(BaseModel):
    """Evento de entrada normalizado, emitido por adaptadores para o gateway."""

    connection_id: str
    conversation_external_id: str
    contact_external_id: str
    contact_name: str = ""
    contact_username: str = ""
    avatar_url: str | None = None
    message_external_id: str
    direction: Literal["incoming", "outgoing_echo"] = "incoming"
    text: str = ""
    sent_at: datetime
    reply_to: str | None = None
    attachments: list[Attachment] = Field(default_factory=list)
