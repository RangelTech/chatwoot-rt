"""Adaptador do TikTok: um worker (processo isolado) por conta, protocolo JSON-lines.

O worker (`tiktok_worker.worker`) roda o ReLttk (login por QR + 2FA, tempo real, envio) ou o
driver fake. Aqui ficam: o gerenciador de processos (um por conexao, sessao em diretorio proprio,
sem varredura compartilhada), a traducao dos passos de login e a ponte de eventos para o gateway.
O codigo de verificacao trafega so por stdin do worker; nada de segredo em argv/env/log.
"""

from __future__ import annotations

import asyncio
import contextlib
import itertools
import json
import logging
import os
import sys
import time
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from app.channels.models import (
    Attachment,
    ConnectionCtx,
    Health,
    InboundMessage,
    QrInfo,
    Step,
    StepField,
    StepView,
    WaitInfo,
)
from app.channels.providers.base import EventSink, ProviderError
from app.channels.states import State

log = logging.getLogger("channels.tiktok")

CALL_TIMEOUT_S = 40.0
CODE_FIELD = "verification_code"


class WorkerProcess:
    """Um processo de worker com request/response por id e fluxo de eventos."""

    def __init__(self, argv: list[str], on_event: Callable[[dict], Awaitable[None]]):
        self._argv = argv
        self._on_event = on_event
        self._proc: asyncio.subprocess.Process | None = None
        self._ids = itertools.count(1)
        self._pending: dict[int, asyncio.Future] = {}
        self._reader: asyncio.Task | None = None

    @property
    def alive(self) -> bool:
        return self._proc is not None and self._proc.returncode is None

    async def start(self) -> None:
        self._proc = await asyncio.create_subprocess_exec(
            *self._argv,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
            limit=1_000_000,
        )
        self._reader = asyncio.create_task(self._read())

    async def _read(self) -> None:
        assert self._proc and self._proc.stdout
        try:
            while True:
                line = await self._proc.stdout.readline()
                if not line:
                    break
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if "id" in obj and ("ok" in obj):
                    fut = self._pending.pop(obj["id"], None)
                    if fut and not fut.done():
                        fut.set_result(obj)
                elif "event" in obj:
                    try:
                        await self._on_event(obj)
                    except Exception:  # um evento ruim nao derruba a leitura
                        log.exception("evento do worker falhou")
        finally:
            for fut in self._pending.values():
                if not fut.done():
                    fut.set_exception(ProviderError("provider_unavailable", "worker encerrou"))
            self._pending.clear()

    async def call(
        self, cmd: str, args: dict[str, Any] | None = None, timeout: float = CALL_TIMEOUT_S
    ) -> dict[str, Any]:
        if not self.alive or not self._proc or not self._proc.stdin:
            raise ProviderError("provider_unavailable", "worker parado")
        rid = next(self._ids)
        fut: asyncio.Future = asyncio.get_running_loop().create_future()
        self._pending[rid] = fut
        line = json.dumps({"id": rid, "cmd": cmd, "args": args or {}}, separators=(",", ":"))
        self._proc.stdin.write((line + "\n").encode())
        await self._proc.stdin.drain()
        try:
            resp = await asyncio.wait_for(fut, timeout)
        except TimeoutError as exc:
            self._pending.pop(rid, None)
            raise ProviderError("timeout", f"{cmd} sem resposta") from exc
        if not resp.get("ok"):
            raise ProviderError(str(resp.get("error_code") or "provider_unavailable"))
        return resp.get("result") or {}

    async def stop(self) -> None:
        if not self._proc:
            return
        with contextlib.suppress(Exception):
            if self.alive:
                await self.call("drain", timeout=5)
        if self.alive:
            with contextlib.suppress(ProcessLookupError):
                self._proc.terminate()
            with contextlib.suppress(Exception):
                await asyncio.wait_for(self._proc.wait(), 5)
        if self.alive:
            with contextlib.suppress(ProcessLookupError):
                self._proc.kill()
        if self._reader:
            self._reader.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await self._reader


class SubprocessLauncher:
    """Dev/QA: o worker roda como subprocesso do gateway (driver fake ou relttk instalado)."""

    def __init__(self, sessions_root: Path, driver: str = "fake", qr_ttl: float = 60.0):
        self.root = sessions_root
        self.driver = driver
        self.qr_ttl = qr_ttl

    def session_dir(self, ctx: ConnectionCtx) -> Path:
        # sessao isolada por tenant e conexao: nenhum worker enxerga o diretorio de outro
        return self.root / str(ctx.account_id) / ctx.id

    def argv(self, ctx: ConnectionCtx) -> list[str]:
        d = self.session_dir(ctx)
        d.mkdir(parents=True, exist_ok=True)
        with contextlib.suppress(OSError):
            os.chmod(d, 0o700)
        return [
            sys.executable,
            "-m",
            "tiktok_worker.worker",
            "--driver",
            self.driver,
            "--session-dir",
            str(d),
            "--qr-ttl",
            str(self.qr_ttl),
        ]


class DockerLauncher(SubprocessLauncher):
    """Producao: `docker run -i` por conta, com limites e volume proprio (ver stacks/canais).

    Exige acesso ao Docker; por seguranca, so atraves de um proxy de socket restrito
    (docker-socket-proxy) ou de um gerenciador dedicado. Nunca montar o socket cru no gateway.
    """

    def __init__(self, sessions_root: Path, image: str, host_root: str, network: str):
        super().__init__(sessions_root, driver="relttk")
        self.image, self.host_root, self.network = image, host_root, network

    def argv(self, ctx: ConnectionCtx) -> list[str]:
        self.session_dir(ctx).mkdir(parents=True, exist_ok=True)
        host_dir = f"{self.host_root}/{ctx.account_id}/{ctx.id}"
        return [
            "docker", "run", "-i", "--rm",
            "--name", f"luar-tiktok-{ctx.id[:12]}",
            "--network", self.network,
            "--memory", "384m", "--cpus", "0.5", "--pids-limit", "128",
            "--read-only", "--tmpfs", "/tmp:size=64m",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
            "-v", f"{host_dir}:/sessao",
            "--label", "rt.service=canais-tiktok-worker",
            self.image, "--driver", "relttk", "--session-dir", "/sessao",
        ]  # fmt: skip


def _dt(value: str | float | None) -> datetime:
    if isinstance(value, str):
        return datetime.fromisoformat(value)
    return datetime.fromtimestamp(float(value or time.time()), UTC)


class TikTokAdapter:
    name = "tiktok"

    def __init__(self, launcher: SubprocessLauncher, sink: EventSink | None = None):
        self._launcher = launcher
        self.sink = sink
        self._procs: dict[str, WorkerProcess] = {}
        self._qr: dict[str, tuple[str, float]] = {}

    # --- processos ---------------------------------------------------------------
    async def _proc(self, ctx: ConnectionCtx, *, create: bool = True) -> WorkerProcess:
        p = self._procs.get(ctx.id)
        if p and p.alive:
            return p
        if not create:
            raise ProviderError("provider_unavailable", "worker parado")

        async def on_event(ev: dict) -> None:
            await self._event(ctx, ev)

        p = WorkerProcess(self._launcher.argv(ctx), on_event)
        await p.start()
        self._procs[ctx.id] = p
        return p

    async def _event(self, ctx: ConnectionCtx, ev: dict) -> None:
        if self.sink is None:
            return
        kind = ev.get("event")
        if kind == "message":
            m = ev["message"]
            await self.sink.on_message(
                InboundMessage(
                    connection_id=ctx.id,
                    conversation_external_id=str(m["conversation_id"]),
                    contact_external_id=str(m.get("contact_id") or m["conversation_id"]),
                    contact_name=m.get("contact_name", ""),
                    contact_username=m.get("contact_username", ""),
                    message_external_id=str(m["message_id"]),
                    direction=m.get("direction", "incoming"),
                    text=m.get("text", ""),
                    sent_at=_dt(m.get("sent_at")),
                )
            )
        elif kind == "session_invalid":
            await self.sink.on_session_invalid(ctx.id, ev.get("error_code", "session_invalid"))
        elif kind == "degraded":
            await self.sink.on_degraded(ctx.id, ev.get("error_code", "provider_unavailable"))
        elif kind == "recovered":
            await self.sink.on_recovered(ctx.id)

    async def restore(self, ctx: ConnectionCtx) -> bool:
        """Apos reinicio do gateway: religa o worker da conexao (sessao salva no volume)."""
        try:
            p = await self._proc(ctx)
            await p.call("connect")
            return True
        except ProviderError:
            return False

    # --- login -------------------------------------------------------------------
    def _qr_view(self, ctx: ConnectionCtx, qr: str, expires_at: float) -> StepView:
        now = time.time()
        return StepView(
            state=State.PENDING_AUTH,
            step=Step(
                step_id="tiktok.qr",
                kind="qr",
                instructions_key="channels.step.qr_tiktok",
                qr=QrInfo(
                    data=qr,
                    expires_at=datetime.fromtimestamp(expires_at, UTC),
                    refresh_after_s=max(5, int(expires_at - now)),
                ),
                wait=WaitInfo(poll_after_s=2, can_cancel=True),
            ),
        )

    async def start_login(self, ctx: ConnectionCtx, flow: str | None) -> StepView:
        p = await self._proc(ctx)
        res = await p.call("login_start")
        self._qr[ctx.id] = (res["qr"], float(res["expires_at"]))
        return self._qr_view(ctx, res["qr"], float(res["expires_at"]))

    async def poll_step(self, ctx: ConnectionCtx) -> StepView:
        p = await self._proc(ctx, create=False)
        res = await p.call("login_poll")
        status = res.get("status")
        if status == "connected":
            await p.call("connect")
            return StepView(
                state=State.CONNECTED,
                step=Step(step_id="tiktok.complete", kind="complete"),
                login_id=ctx.id,
            )
        if status == "needs_code":
            return StepView(
                state=State.AWAITING_2FA,
                step=Step(
                    step_id="tiktok.code",
                    kind="code_2fa",
                    instructions_key="channels.step.code_2fa",
                    fields=[
                        StepField(
                            id=CODE_FIELD,
                            type="2fa_code",
                            label_key=f"channels.field.{CODE_FIELD}",
                            secret=True,
                        )
                    ],
                ),
            )
        if status == "expired":
            return await self.start_login(ctx, None)  # QR novo, mesma conexao
        cur = self._qr.get(ctx.id)
        if not cur:
            return await self.start_login(ctx, None)
        return self._qr_view(ctx, *cur)

    async def submit_step(
        self, ctx: ConnectionCtx, step_id: str, kind: str, data: dict[str, str]
    ) -> StepView:
        if kind != "code_2fa":
            raise ProviderError("unsupported_step")
        p = await self._proc(ctx, create=False)
        code = (data.get(CODE_FIELD) or data.get("code") or "").strip()
        await p.call("login_code", {"code": code})  # wrong_code sobe como ProviderError
        return await self.poll_step(ctx)

    def last_step(self, ctx: ConnectionCtx) -> Step | None:
        return None

    async def cancel_login(self, ctx: ConnectionCtx) -> None:
        self._qr.pop(ctx.id, None)
        p = self._procs.pop(ctx.id, None)
        if p:
            with contextlib.suppress(ProviderError):
                await p.call("login_cancel", timeout=5)
            await p.stop()

    async def logout(self, ctx: ConnectionCtx) -> None:
        p = self._procs.pop(ctx.id, None)
        if p is None:
            with contextlib.suppress(ProviderError):
                p = await self._proc(ctx)
        if p:
            with contextlib.suppress(ProviderError):
                await p.call("logout", timeout=15)
            await p.stop()

    # --- mensagens ---------------------------------------------------------------
    async def send(
        self,
        ctx: ConnectionCtx,
        conversation_ref: str,
        text: str,
        attachments: list[Attachment],
        reply_to: str | None,
    ) -> str:
        if attachments:
            raise ProviderError("unsupported_step", "midia so depois de testada (CH-5)")
        p = await self._ready(ctx)
        res = await p.call(
            "send",
            {
                "conversation": conversation_ref,
                "text": text,
                "client_msg_id": "",
                "reply_to": reply_to,
            },
        )
        return str(res["external_id"])

    async def _ready(self, ctx: ConnectionCtx) -> WorkerProcess:
        p = self._procs.get(ctx.id)
        if p and p.alive:
            return p
        p = await self._proc(ctx)
        await p.call("connect")
        return p

    async def sync(self, ctx: ConnectionCtx, since_days: int) -> None:
        p = await self._ready(ctx)
        since = (datetime.now(UTC) - timedelta(days=since_days)).timestamp()
        res = await p.call("sync", {"since_ts": since}, timeout=120)
        if self.sink is None:
            return
        for m in res.get("messages", []):
            await self._event(ctx, {"event": "message", "message": m})

    async def health(self, ctx: ConnectionCtx) -> Health:
        p = self._procs.get(ctx.id)
        if not p or not p.alive:
            return Health(process=False, session=False, io=False)
        try:
            h = await p.call("health", timeout=10)
        except ProviderError:
            return Health(process=True, session=False, io=False)
        return Health(process=True, session=bool(h.get("session")), io=bool(h.get("io")))
