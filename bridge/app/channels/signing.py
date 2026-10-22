"""Assinatura HMAC do webhook gateway -> Rails (ver CONTRATO_GATEWAY.md)."""

from __future__ import annotations

import hashlib
import hmac
import time


def sign(secret: str, timestamp: int, body: bytes) -> str:
    mac = hmac.new(secret.encode(), f"{timestamp}.".encode() + body, hashlib.sha256)
    return "sha256=" + mac.hexdigest()


def headers(secret: str, event_id: str, body: bytes, now: int | None = None) -> dict[str, str]:
    ts = int(now if now is not None else time.time())
    return {
        "Content-Type": "application/json",
        "X-Luar-Event-Id": event_id,
        "X-Luar-Timestamp": str(ts),
        "X-Luar-Signature": sign(secret, ts, body),
    }


def verify(
    secret: str,
    timestamp: str,
    signature: str,
    body: bytes,
    tolerance_s: int = 300,
    now: int | None = None,
) -> bool:
    try:
        ts = int(timestamp)
    except (TypeError, ValueError):
        return False
    if abs((now if now is not None else time.time()) - ts) > tolerance_s:
        return False
    return hmac.compare_digest(sign(secret, ts, body), signature or "")
