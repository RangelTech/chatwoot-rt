"""TikTok simulado (QA/CDP): worker com driver fake que "escaneia" o QR sozinho."""

from __future__ import annotations

import asyncio
import contextlib

from app.channels.models import ConnectionCtx, StepView
from app.channels.providers.base import ProviderError
from app.channels.providers.tiktok import TikTokAdapter


class SimTikTokAdapter(TikTokAdapter):
    def __init__(self, launcher, sink=None, *, scan_after_s: float = 20.0):
        super().__init__(launcher, sink)
        self._scan_after_s = scan_after_s
        self._scans: dict[str, asyncio.Task] = {}

    async def start_login(self, ctx: ConnectionCtx, flow: str | None) -> StepView:
        view = await super().start_login(ctx, flow)
        old = self._scans.pop(ctx.id, None)
        if old:
            old.cancel()
        self._scans[ctx.id] = asyncio.create_task(self._auto_scan(ctx))
        return view

    async def _auto_scan(self, ctx: ConnectionCtx) -> None:
        await asyncio.sleep(self._scan_after_s)
        p = self._procs.get(ctx.id)
        if p is None:
            return
        with contextlib.suppress(ProviderError):
            await p.call("fake", {"op": "scan"}, timeout=5)

    async def cancel_login(self, ctx: ConnectionCtx) -> None:
        task = self._scans.pop(ctx.id, None)
        if task:
            task.cancel()
        await super().cancel_login(ctx)

    async def simulate_inbound(self, ctx: ConnectionCtx, **args) -> None:
        p = self._procs.get(ctx.id)
        if p is None:
            raise ProviderError("provider_unavailable", "worker parado")
        await p.call("fake", {"op": "inbound", **args}, timeout=5)
