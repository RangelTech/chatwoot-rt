"""Credenciais de canal cifradas em repouso (Fernet).

Mesmo contrato do `agent-platform/backend/app/crypto.py`: chave mestra vem do
ambiente em produção; em desenvolvimento cai para uma chave derivada, com
aviso, para ninguém achar que está protegido quando não está.
"""

import base64
import hashlib
import logging
from functools import lru_cache

from cryptography.fernet import Fernet

from app.config import settings

logger = logging.getLogger(__name__)

_DEV_SEED = "chatwoot-rt-dev-only"


@lru_cache(maxsize=1)
def _fernet() -> Fernet:
    key = settings.encryption_key.strip()
    if not key:
        logger.warning(
            "ENCRYPTION_KEY ausente: usando chave derivada de desenvolvimento. "
            "Não use isso em produção."
        )
        key = base64.urlsafe_b64encode(hashlib.sha256(_DEV_SEED.encode()).digest()).decode()
    return Fernet(key.encode())


def encrypt(value: str) -> str:
    return _fernet().encrypt(value.encode()).decode()


def decrypt(value: str | None) -> str:
    if not value:
        return ""
    return _fernet().decrypt(value.encode()).decode()
