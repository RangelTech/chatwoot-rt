"""Drivers do worker: fachada `ReLttkDriver` (integração real) e `FakeTikTokDriver` (testes).

O ReLttk (MIT) NÃO é copiado para este repositório: é instalado por commit fixado na imagem do
worker (ver README.md) e importado tardiamente, só dentro de `ReLttkDriver`.
"""

from __future__ import annotations

import asyncio
import json
import os
import queue
import random
import threading
import time
from abc import ABC, abstractmethod
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

Emit = Callable[[dict[str, Any]], Awaitable[None]]

# Códigos estáveis (alinhados ao `error_code` do CONTRATO_GATEWAY.md).
WRONG_CODE = "wrong_code"
SESSION_INVALID = "session_invalid"
NOT_CONNECTED = "not_connected"
PROVIDER_UNAVAILABLE = "provider_unavailable"
UNSUPPORTED = "unsupported_step"


class DriverError(Exception):
    def __init__(self, code: str, detail: str = ""):
        super().__init__(code)
        self.code = code
        self.detail = detail  # nunca inclui credencial


class TikTokDriver(ABC):
    """Contrato interno do worker. Uma instância por processo (uma conta)."""

    def __init__(self, session_dir: Path, emit: Emit):
        self.session_dir = session_dir
        self.emit = emit

    @abstractmethod
    async def open(self) -> bool:
        """True se já existe sessão salva neste diretório."""

    @abstractmethod
    async def login_start(self) -> dict[str, Any]:
        """Gera um QR: {"qr": <texto/URL do QR>, "expires_at": <epoch s>}."""

    @abstractmethod
    async def login_poll(self) -> dict[str, Any]:
        """{"status": waiting|scanned|needs_code|expired|connected, "contact_hint"?}."""

    @abstractmethod
    async def login_code(self, code: str) -> dict[str, Any]:
        """Envia o código de verificação. Levanta DriverError(wrong_code). {"retry": bool}."""

    @abstractmethod
    async def login_cancel(self) -> None: ...

    @abstractmethod
    async def connect(self) -> dict[str, Any]:
        """Abre o tempo real com a sessão salva. Levanta DriverError(session_invalid)."""

    @abstractmethod
    async def send(
        self, conversation: str, text: str, client_msg_id: str, reply_to: str | None
    ) -> str:
        """Retorna o id externo da mensagem."""

    @abstractmethod
    async def history(self, since_ts: float) -> list[dict[str, Any]]: ...

    @abstractmethod
    async def health(self) -> dict[str, bool]:
        """{"session": bool, "io": bool}."""

    @abstractmethod
    async def logout(self) -> None: ...

    @abstractmethod
    async def close(self) -> None: ...

    async def control(self, op: str, args: dict[str, Any]) -> dict[str, Any]:
        raise DriverError(UNSUPPORTED, "control só existe no driver fake")


def _iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, UTC).isoformat()


class FakeTikTokDriver(TikTokDriver):
    """Simulador determinístico: QR que expira/renova, 2FA, entrada, envio e queda de sessão.

    Controlado pelo comando `fake` (ver `control`): scan, expire_qr, require_code, inbound,
    drop, degrade, recover, crash, fail_next_send.
    """

    CODE = "123456"
    SESSION_FILE = "session.json"
    HISTORY_FILE = "history.json"

    def __init__(self, session_dir: Path, emit: Emit, *, qr_ttl: float = 60.0, clock=time.time):
        super().__init__(session_dir, emit)
        self._ttl = qr_ttl
        self._clock = clock
        self._qr_seq = 0
        self._qr_expires = 0.0
        self._scanned = False
        self._require_code = False
        self._code_ok = False
        self._connected = False
        self._io = False
        self._fail_send = 0
        self._msg_seq = 0
        self._sent_seq = 0

    def _session_path(self) -> Path:
        return self.session_dir / self.SESSION_FILE

    def _read_history(self) -> list[dict[str, Any]]:
        p = self.session_dir / self.HISTORY_FILE
        return json.loads(p.read_text("utf-8")) if p.exists() else []

    def _append_history(self, msg: dict[str, Any]) -> None:
        h = self._read_history()
        h.append(msg)
        (self.session_dir / self.HISTORY_FILE).write_text(json.dumps(h), "utf-8")

    async def open(self) -> bool:
        return self._session_path().exists()

    async def login_start(self) -> dict[str, Any]:
        self._qr_seq += 1
        self._qr_expires = self._clock() + self._ttl
        self._scanned = False
        self._code_ok = False
        qr = f"https://fake.tiktok.test/qr/{self.session_dir.name}-{self._qr_seq}"
        return {"qr": qr, "expires_at": self._qr_expires}

    async def login_poll(self) -> dict[str, Any]:
        if self._qr_seq == 0:
            raise DriverError(NOT_CONNECTED, "login não iniciado")
        if not self._scanned and self._clock() >= self._qr_expires:
            return {"status": "expired"}
        if not self._scanned:
            return {"status": "waiting"}
        if self._require_code and not self._code_ok:
            return {"status": "needs_code", "contact_hint": "e***@exemplo.test"}
        self._session_path().write_text(json.dumps({"token": f"fake-{self._qr_seq}"}), "utf-8")
        os.chmod(self._session_path(), 0o600)
        return {"status": "connected"}

    async def login_code(self, code: str) -> dict[str, Any]:
        if not (self._scanned and self._require_code):
            raise DriverError(NOT_CONNECTED, "sem verificação pendente")
        if code != self.CODE:
            raise DriverError(WRONG_CODE)
        self._code_ok = True
        return {"retry": True}

    async def login_cancel(self) -> None:
        self._qr_seq = 0
        self._scanned = False
        self._qr_expires = 0.0

    async def connect(self) -> dict[str, Any]:
        if not self._session_path().exists():
            raise DriverError(SESSION_INVALID)
        self._connected = True
        self._io = True
        return {"account": {"user_id": f"u-{self.session_dir.name}", "username": "conta_fake"}}

    async def send(self, conversation, text, client_msg_id, reply_to):
        if not self._io:
            raise DriverError(NOT_CONNECTED)
        if self._fail_send > 0:
            self._fail_send -= 1
            raise DriverError(PROVIDER_UNAVAILABLE, "falha simulada")
        self._sent_seq += 1
        ext = f"sent-{self.session_dir.name}-{self._sent_seq}"
        self._append_history(
            {
                "conversation_id": conversation,
                "contact_id": conversation,
                "message_id": ext,
                "direction": "outgoing_echo",
                "text": text,
                "sent_at": _iso(self._clock()),
            }
        )
        return ext

    async def history(self, since_ts: float) -> list[dict[str, Any]]:
        return [
            m
            for m in self._read_history()
            if datetime.fromisoformat(m["sent_at"]).timestamp() >= since_ts
        ]

    async def health(self) -> dict[str, bool]:
        return {"session": self._connected and self._session_path().exists(), "io": self._io}

    async def logout(self) -> None:
        self._connected = False
        self._io = False
        for name in (self.SESSION_FILE, self.HISTORY_FILE):
            (self.session_dir / name).unlink(missing_ok=True)

    async def close(self) -> None:
        self._io = False

    async def control(self, op: str, args: dict[str, Any]) -> dict[str, Any]:
        if op == "scan":
            if self._qr_seq == 0:
                raise DriverError(NOT_CONNECTED, "sem QR")
            self._scanned = True
        elif op == "expire_qr":
            self._qr_expires = 0.0
        elif op == "require_code":
            self._require_code = bool(args.get("value", True))
        elif op == "fail_next_send":
            self._fail_send = int(args.get("n", 1))
        elif op == "inbound":
            self._msg_seq += 1
            ts = float(args.get("ts", self._clock()))
            msg = {
                "conversation_id": args.get("conversation", "0:1:100:200"),
                "contact_id": args.get("contact", "100"),
                "contact_name": args.get("name", "Contato Fake"),
                "contact_username": args.get("username", "contato_fake"),
                "message_id": args.get("id", f"in-{self.session_dir.name}-{self._msg_seq}"),
                "direction": args.get("direction", "incoming"),
                "text": args.get("text", "oi"),
                "sent_at": _iso(ts),
            }
            self._append_history(msg)
            if self._io:
                await self.emit({"event": "message", "message": msg})
        elif op == "drop":
            self._connected = False
            self._io = False
            self._session_path().unlink(missing_ok=True)
            await self.emit({"event": "session_invalid", "error_code": SESSION_INVALID})
        elif op == "degrade":
            self._io = False
            await self.emit({"event": "degraded", "error_code": PROVIDER_UNAVAILABLE})
        elif op == "recover":
            self._io = True
            await self.emit({"event": "recovered"})
        elif op == "crash":
            os._exit(17)
        else:
            raise DriverError(UNSUPPORTED, f"op desconhecida: {op}")
        return {}


class ReLttkDriver(TikTokDriver):
    """Fachada sobre o ReLttk instalado por commit fixado (importação tardia).

    NÃO VALIDADO SEM CONTA REAL (CH-0(c)). Pontos de atenção do ReLttk tratados aqui:
    - `qrlogin` é bloqueante, imprime o QR e usa `input()` para o 2FA: roda em thread, com
      `_print_qr`/`input` substituídos por filas;
    - `_SESSION_DIR` e o `messages.db` do cliente ficam no diretório do pacote por padrão (seriam
      compartilhados entre contas): ambos são redirecionados para o diretório da conta;
    - `config.*` é global do módulo: por isso 1 processo por conta (nunca 2 contas por processo).
    """

    def __init__(self, session_dir: Path, emit: Emit, *, package: str = "relttk"):
        super().__init__(session_dir, emit)
        self._pkg_name = package
        self._pkg: Any = None
        self._qr: Any = None
        self._qr_q: queue.Queue[str] = queue.Queue()
        self._code_q: queue.Queue[str | None] = queue.Queue()
        self._need_code = threading.Event()
        self._login_thread: threading.Thread | None = None
        self._login_result: dict[str, Any] | None = None
        self._login_error: str | None = None
        self._client: Any = None
        self._run_task: asyncio.Task | None = None

    def _load(self):
        if self._pkg is None:
            import importlib

            self._pkg = importlib.import_module(self._pkg_name)
            qr = importlib.import_module(f"{self._pkg_name}.qrlogin")
            qr._SESSION_DIR = str(self.session_dir)
            qr._print_qr = lambda url: self._qr_q.put(url)
            qr.input = lambda _prompt="": self._wait_code()
            self._qr = qr
        return self._pkg

    def _wait_code(self) -> str:
        self._need_code.set()
        code = self._code_q.get()
        self._need_code.clear()
        return code or ""

    async def open(self) -> bool:
        self._load()
        return (self.session_dir / "session.json").exists()

    async def login_start(self) -> dict[str, Any]:
        self._load()
        await self.login_cancel()
        self._login_result = None
        self._login_error = None
        self._qr._stop_event.clear()
        did = str(random.randint(7_000_000_000_000_000_000, 7_999_999_999_999_999_999))

        def _run():
            try:
                self._login_result = self._qr._try_login(did)
            except Exception as exc:  # _TwoFAFailed etc.
                self._login_error = type(exc).__name__

        self._login_thread = threading.Thread(target=_run, daemon=True)
        self._login_thread.start()
        loop = asyncio.get_running_loop()
        try:
            url = await asyncio.wait_for(loop.run_in_executor(None, self._qr_q.get), 30)
        except TimeoutError as exc:
            raise DriverError(PROVIDER_UNAVAILABLE, "QR não gerado") from exc
        # TTL do QR do TikTok: confirmar com conta real (CH-0c). Valor conservador.
        return {"qr": url, "expires_at": time.time() + 120}

    async def login_poll(self) -> dict[str, Any]:
        if self._login_thread is None:
            raise DriverError(NOT_CONNECTED, "login não iniciado")
        if self._need_code.is_set():
            return {"status": "needs_code"}
        if self._login_thread.is_alive():
            return {"status": "waiting"}
        if self._login_result and self._login_result.get("sessionid"):
            self._qr._write_cookies(self._login_result, "session")
            os.chmod(self.session_dir / "session.json", 0o600)
            return {"status": "connected"}
        return {"status": "expired"}

    async def login_code(self, code: str) -> dict[str, Any]:
        if not self._need_code.is_set():
            raise DriverError(NOT_CONNECTED, "sem verificação pendente")
        self._code_q.put(code)
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, self._login_thread.join, 20)
        # O ReLttk encerra o login inteiro se o código estiver errado (_TwoFAFailed).
        if self._login_error == "_TwoFAFailed":
            raise DriverError(WRONG_CODE)
        return {"retry": False}

    async def login_cancel(self) -> None:
        if self._qr is None:
            return
        self._qr._stop_event.set()
        self._code_q.put(None)
        if self._login_thread and self._login_thread.is_alive():
            self._login_thread.join(5)
        self._login_thread = None

    async def connect(self) -> dict[str, Any]:
        pkg = self._load()
        if not (self.session_dir / "session.json").exists():
            raise DriverError(SESSION_INVALID)
        client = pkg.LttkClient(username="session", managed=True)
        self._redirect_msg_db(client)
        client._dispatch = self._dispatch
        self._client = client
        self._run_task = asyncio.create_task(client.run())
        self._run_task.add_done_callback(self._on_run_done)
        for _ in range(100):
            if getattr(client, "websocket", None) is not None:
                return {"account": {"user_id": client._own_user_id}}
            if self._run_task.done():
                break
            await asyncio.sleep(0.2)
        raise DriverError(SESSION_INVALID)

    def _redirect_msg_db(self, client: Any) -> None:
        # O ReLttk grava messages.db no diretório do pacote (compartilhado): isola por conta.
        import sqlite3

        db = sqlite3.connect(str(self.session_dir / "messages.db"), check_same_thread=False)
        db.execute(
            "CREATE TABLE IF NOT EXISTS messages (msg_id TEXT PRIMARY KEY, conv_id TEXT,"
            " sender_id TEXT, awe_type INTEGER, ts INTEGER, data TEXT)"
        )
        client._msg_db = db

    def _on_run_done(self, task: asyncio.Task) -> None:
        if not task.cancelled():
            asyncio.get_running_loop().create_task(
                self.emit({"event": "session_invalid", "error_code": SESSION_INVALID})
            )

    async def _dispatch(self, msg: dict[str, Any]) -> None:
        if not msg.get("msg_id") or not msg.get("conv_id"):
            return  # só texto nesta versão; mídia só depois de testada (CH-5)
        mine = str(msg.get("sender_id")) == str(self._client._own_user_id)
        await self.emit(
            {
                "event": "message",
                "message": {
                    "conversation_id": msg["conv_id"],
                    "contact_id": str(msg.get("sender_id", "")),
                    "message_id": str(msg["msg_id"]),
                    "direction": "outgoing_echo" if mine else "incoming",
                    "text": msg.get("text") or "",
                    "sent_at": _iso(time.time()),
                },
            }
        )

    async def send(self, conversation, text, client_msg_id, reply_to):
        if self._client is None or self._client.websocket is None:
            raise DriverError(NOT_CONNECTED)
        _msg_type, client_id = await self._client.send_message(conversation, text)
        return str(client_id)

    async def history(self, since_ts: float) -> list[dict[str, Any]]:
        if self._client is None:
            raise DriverError(NOT_CONNECTED)
        out: list[dict[str, Any]] = []
        for conv in await self._client.get_conversations():
            conv_id = conv.get("conv_id") or conv.get("id")
            if not conv_id:
                continue
            for m in await self._client.fetch_history(conv_id, count=50):
                ts = float(m.get("ts") or 0)
                if ts >= since_ts and m.get("msg_id"):
                    out.append(
                        {
                            "conversation_id": conv_id,
                            "contact_id": str(m.get("sender_id", "")),
                            "message_id": str(m["msg_id"]),
                            "direction": "incoming",
                            "text": m.get("text", ""),
                            "sent_at": _iso(ts),
                        }
                    )
        return out

    async def health(self) -> dict[str, bool]:
        ws = getattr(self._client, "websocket", None)
        return {"session": self._client is not None, "io": ws is not None}

    async def logout(self) -> None:
        if self._client is not None:
            await self._client.close_session()
        await self.close()

    async def close(self) -> None:
        if self._run_task and not self._run_task.done():
            self._run_task.cancel()
        self._client = None


def make_driver(name: str, session_dir: Path, emit: Emit, **opts: Any) -> TikTokDriver:
    if name == "fake":
        return FakeTikTokDriver(session_dir, emit, **opts)
    if name == "relttk":
        return ReLttkDriver(session_dir, emit, **opts)
    raise ValueError(f"driver desconhecido: {name}")
