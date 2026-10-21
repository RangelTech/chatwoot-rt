"""Worker de TikTok: um processo por conta, JSON-lines por stdin/stdout (ver protocol.py).

Uso: python -m tiktok_worker.worker --driver fake|relttk --session-dir DIR [--max-mem-mb N]

Nenhum segredo em argv/env: o código de verificação chega só por stdin e nunca é logado.
O stdout é reservado ao protocolo; qualquer print de bibliotecas vai para o stderr.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import stat
import sys
import threading
from pathlib import Path
from typing import Any

from tiktok_worker import protocol
from tiktok_worker.drivers import DriverError, TikTokDriver, make_driver


def rss_bytes() -> int:
    """Memória residente deste processo (stdlib apenas)."""
    if sys.platform == "win32":
        import ctypes
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD),
                ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t),
            ]

        c = Counters()
        c.cb = ctypes.sizeof(c)
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.GetCurrentProcess.restype = wintypes.HANDLE
        psapi = ctypes.WinDLL("psapi", use_last_error=True)
        psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
        if psapi.GetProcessMemoryInfo(k32.GetCurrentProcess(), ctypes.byref(c), c.cb):
            return int(c.WorkingSetSize)
        return 0
    try:
        with open("/proc/self/statm") as f:
            return int(f.read().split()[1]) * os.sysconf("SC_PAGE_SIZE")
    except OSError:
        import resource

        return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * 1024


def apply_limits(max_mem_mb: int) -> None:
    """rlimit onde houver (POSIX). No Windows o limite fica a cargo do contêiner/cgroup."""
    try:
        import resource
    except ImportError:
        return
    if max_mem_mb > 0:
        limit = max_mem_mb * 1024 * 1024
        resource.setrlimit(resource.RLIMIT_AS, (limit, limit))
    resource.setrlimit(resource.RLIMIT_NOFILE, (256, 256))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))  # core dump poderia vazar a sessão


def check_session_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    if os.name == "posix":
        os.chmod(path, 0o700)
        if stat.S_IMODE(path.stat().st_mode) & 0o077:
            raise SystemExit("diretório de sessão com permissão aberta")


class Worker:
    def __init__(self, driver_name: str, session_dir: Path, out, **driver_opts: Any):
        self._out = out
        self._lock = threading.Lock()
        self._stop = asyncio.Event()
        self.driver_name = driver_name
        self.driver: TikTokDriver = make_driver(driver_name, session_dir, self.emit, **driver_opts)

    async def emit(self, obj: dict[str, Any]) -> None:
        data = protocol.encode(obj)
        with self._lock:
            self._out.write(data)
            self._out.flush()

    async def handle(self, req: dict[str, Any]) -> None:
        rid = req.get("id")
        cmd = req.get("cmd")
        args = req.get("args") or {}
        try:
            if cmd not in protocol.COMMANDS:
                raise DriverError("unsupported_step", f"comando desconhecido: {cmd}")
            result = await self._run(str(cmd), args)
            await self.emit({"id": rid, "ok": True, "result": result})
        except DriverError as exc:
            await self.emit({"id": rid, "ok": False, "error_code": exc.code, "detail": exc.detail})
        except Exception as exc:
            # só o tipo: a mensagem de uma exceção poderia conter dado de sessão.
            await self.emit(
                {"id": rid, "ok": False, "error_code": "internal", "detail": type(exc).__name__}
            )
        if cmd == "drain":
            self._stop.set()

    async def _run(self, cmd: str, args: dict[str, Any]) -> dict[str, Any]:
        d = self.driver
        if cmd == "login_start":
            return await d.login_start()
        if cmd == "login_poll":
            return await d.login_poll()
        if cmd == "login_code":
            return await d.login_code(str(args.get("code", "")))
        if cmd == "login_cancel":
            await d.login_cancel()
            return {}
        if cmd == "connect":
            res = await d.connect()
            await self.emit({"event": "ready"})
            return res
        if cmd == "send":
            ext = await d.send(
                str(args["conversation"]),
                str(args.get("text", "")),
                str(args.get("client_msg_id", "")),
                args.get("reply_to"),
            )
            return {"external_id": ext}
        if cmd == "sync":
            return {"messages": await d.history(float(args.get("since_ts", 0)))}
        if cmd == "health":
            h = await d.health()
            return {**h, "rss_bytes": rss_bytes(), "pid": os.getpid()}
        if cmd == "logout":
            await d.logout()
            return {}
        if cmd == "drain":
            await d.close()
            return {}
        if cmd == "fake":
            if self.driver_name != "fake":
                raise DriverError("unsupported_step", "só com o driver fake")
            return await d.control(str(args.get("op", "")), args)
        raise DriverError("unsupported_step", cmd)

    async def serve(self, stdin) -> None:
        loop = asyncio.get_running_loop()
        q: asyncio.Queue[bytes | None] = asyncio.Queue()

        def reader() -> None:
            for line in iter(stdin.readline, b""):
                loop.call_soon_threadsafe(q.put_nowait, line)
            loop.call_soon_threadsafe(q.put_nowait, None)

        threading.Thread(target=reader, daemon=True).start()
        await self.emit({"event": "ready_process", "pid": os.getpid()})
        tasks: set[asyncio.Task] = set()
        while not self._stop.is_set():
            getter = asyncio.ensure_future(q.get())
            stopper = asyncio.ensure_future(self._stop.wait())
            done, _ = await asyncio.wait({getter, stopper}, return_when=asyncio.FIRST_COMPLETED)
            if getter not in done:
                getter.cancel()
                break
            stopper.cancel()
            line = getter.result()
            if line is None:  # manager fechou o stdin
                break
            try:
                req = protocol.decode(line)
            except ValueError:
                continue
            t = asyncio.create_task(self.handle(req))
            tasks.add(t)
            t.add_done_callback(tasks.discard)
        if tasks:
            await asyncio.wait(tasks, timeout=10)
        await self.driver.close()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--driver", default="relttk", choices=["fake", "relttk"])
    ap.add_argument("--session-dir", required=True)
    ap.add_argument("--max-mem-mb", type=int, default=0)
    ap.add_argument("--qr-ttl", type=float, default=60.0)
    ns = ap.parse_args(argv)
    # Reserva o stdout real para o protocolo; prints de bibliotecas vão para o stderr.
    proto_out = sys.stdout.buffer
    sys.stdout = sys.stderr
    apply_limits(ns.max_mem_mb)
    session_dir = Path(ns.session_dir)
    check_session_dir(session_dir)
    opts = {"qr_ttl": ns.qr_ttl} if ns.driver == "fake" else {}
    worker = Worker(ns.driver, session_dir, proto_out, **opts)
    asyncio.run(worker.serve(sys.stdin.buffer))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
