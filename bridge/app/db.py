"""Acesso ao banco operacional da ponte.

Mesmo padrão do agent-platform: um context manager que commita no sucesso e
faz rollback no erro, com timeout de conexão explícito — banco inacessível
falha rápido em vez de pendurar o processo.
"""

from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row

from app.config import settings


@contextmanager
def get_connection():
    with psycopg.connect(
        settings.database_url,
        row_factory=dict_row,
        connect_timeout=settings.db_connect_timeout,
    ) as conn:
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
