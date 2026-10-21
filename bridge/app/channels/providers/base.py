"""Interface que todo provedor (bridge Matrix ou worker) implementa para o gateway."""

from __future__ import annotations

from typing import Protocol

from app.channels.models import Attachment, ConnectionCtx, Health, InboundMessage, StepView


class EventSink(Protocol):
    """O gateway entrega isto ao adaptador; o adaptador chama ao receber algo do provedor."""

    async def on_message(self, msg: InboundMessage) -> None: ...

    async def on_session_invalid(self, connection_id: str, error_code: str) -> None: ...

    async def on_degraded(self, connection_id: str, error_code: str) -> None: ...

    async def on_recovered(self, connection_id: str) -> None: ...


class ProviderError(Exception):
    """Erro do provedor com código estável (ver `error_code` em CONTRATO_GATEWAY.md)."""

    def __init__(self, error_code: str, detail: str = ""):
        super().__init__(error_code)
        self.error_code = error_code
        self.detail = detail  # nunca inclui credencial


class ProviderAdapter(Protocol):
    name: str

    async def start_login(self, conn: ConnectionCtx, flow: str | None) -> StepView: ...

    async def submit_step(
        self, conn: ConnectionCtx, step_id: str, kind: str, data: dict[str, str]
    ) -> StepView: ...

    async def poll_step(self, conn: ConnectionCtx) -> StepView:
        """Estado atual do login (espera de aprovação / QR renovado)."""
        ...

    async def cancel_login(self, conn: ConnectionCtx) -> None: ...

    async def logout(self, conn: ConnectionCtx) -> None: ...

    async def send(
        self,
        conn: ConnectionCtx,
        conversation_ref: str,
        text: str,
        attachments: list[Attachment],
        reply_to: str | None,
    ) -> str:
        """Retorna o id externo da mensagem enviada."""
        ...

    async def sync(self, conn: ConnectionCtx, since_days: int) -> None: ...

    async def health(self, conn: ConnectionCtx) -> Health: ...
