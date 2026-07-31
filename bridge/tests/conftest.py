"""Fixtures da ponte.

Os testes rodam contra um Postgres real (mesma filosofia do agent-platform):
idempotência e deduplicação são garantidas por índice único no banco, então
testar com banco fake provaria a coisa errada.
"""

import os
import uuid

import psycopg
import pytest
from fastapi.testclient import TestClient

os.environ.setdefault(
    "DATABASE_URL", "postgresql://agent:agent@localhost:5433/chatwoot_bridge_test"
)
os.environ.setdefault("BRIDGE_ADMIN_TOKEN", "token-de-teste")
os.environ.setdefault("ENCRYPTION_KEY", "")


@pytest.fixture(scope="session")
def _schema():
    from app.config import settings
    from app.main import run_migrations

    base = settings.database_url.rsplit("/", 1)[0] + "/postgres"
    name = settings.database_url.rsplit("/", 1)[1].split("?")[0]
    with psycopg.connect(base, autocommit=True) as conn:
        exists = conn.execute("SELECT 1 FROM pg_database WHERE datname = %s", (name,)).fetchone()
        if not exists:
            conn.execute(f'CREATE DATABASE "{name}"')
    run_migrations()


@pytest.fixture
def client(_schema):
    from app.config import settings
    from app.main import app

    with psycopg.connect(settings.database_url, autocommit=True) as conn:
        conn.execute("TRUNCATE tenant_links, channel_events CASCADE")
    return TestClient(app)


@pytest.fixture
def admin_auth():
    from app.config import settings

    return {"Authorization": f"Bearer {settings.bridge_admin_token}"}


@pytest.fixture
def tenant_id():
    return str(uuid.uuid4())
