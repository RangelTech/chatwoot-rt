"""Ponte Rangel Tech — Chatwoot ⇄ agent-platform."""

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from app.api import admin, agent_bot, label_webhook
from app.config import settings
from app.db import get_connection

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"

_BOOTSTRAP = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    filename TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)
"""


def run_migrations() -> list[str]:
    applied: list[str] = []
    with get_connection() as conn:
        conn.execute(_BOOTSTRAP)
        done = {
            r["filename"] for r in conn.execute("SELECT filename FROM schema_migrations").fetchall()
        }
        for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
            if path.name in done:
                continue
            logger.info("aplicando migração %s", path.name)
            conn.execute(path.read_text(encoding="utf-8"))
            conn.execute("INSERT INTO schema_migrations (filename) VALUES (%s)", (path.name,))
            applied.append(path.name)
    return applied


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Sem isso, segredo em repouso (integration_key, etc.) seria cifrado com a
    # chave derivada pública do código-fonte — parece protegido, não está.
    if settings.environment == "production" and not settings.encryption_key.strip():
        raise RuntimeError(
            "ENCRYPTION_KEY é obrigatória com ENVIRONMENT=production — "
            "sem ela, segredos em repouso seriam cifrados com a chave de "
            "desenvolvimento conhecida no código-fonte."
        )
    applied = run_migrations()
    if applied:
        logger.info("migrações aplicadas: %s", applied)
    yield


app = FastAPI(title="chatwoot-rt bridge", lifespan=lifespan)
app.include_router(admin.router)
app.include_router(agent_bot.router)
app.include_router(label_webhook.router)


@app.get("/health")
def health():
    return {"status": "ok"}
