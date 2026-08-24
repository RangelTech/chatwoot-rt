"""Provisionamento privilegiado de instâncias Evolution API por tenant
(produto-05 seção 4 — QR automático).

Esta é a única camada do sistema que sabe SSH na VPS para subir o
container/Postgres/Redis dedicados de uma conexão Evolution. Nem o
navegador do administrador do tenant, nem o Rails do Chatwoot, têm essa
credencial — eles só recebem `inbox_id`, QR e status já sanitizados
(`app/api/admin.py`). A lógica espelha `scripts/provisionar_evolution.py`
(mesmo desenho: 1 container/Postgres/Redis dedicado por conexão, nunca
compartilhado — ver docstring de lá para o porquê), mas roda dentro da
própria ponte (Cloud Run) em vez de precisar de um operador humano rodando
o script na máquina dele, e é idempotente por natureza: nunca recria um
container que já existe, só espera ele ficar saudável.
"""

import asyncio
import logging
import tempfile
from pathlib import Path

from app.config import settings

logger = logging.getLogger(__name__)


class ProvisioningError(Exception):
    pass


def nomes(tenant_id: str, indice: int = 1) -> dict:
    curto = tenant_id.replace("-", "")[:12]
    sufixo = "" if indice <= 1 else f"-{indice}"
    return {
        "evolution": f"evolution-{curto}{sufixo}",
        "postgres": f"evolution-pg-{curto}{sufixo}",
        "redis": f"evolution-redis-{curto}{sufixo}",
        "host": f"evolution-{curto}{sufixo}.{settings.evolution_domain}",
    }


_key_file_lock = asyncio.Lock()
_key_file_path: str | None = None


async def _ssh_key_file() -> str:
    """Materializa a chave privada (vinda do Secret Manager via env) num
    arquivo temporário com permissão 600, uma vez por processo -- o cliente
    ssh não aceita a chave por stdin/flag, só por arquivo."""
    global _key_file_path
    if not settings.evolution_ssh_private_key:
        raise ProvisioningError("EVOLUTION_SSH_PRIVATE_KEY não configurada na ponte")
    async with _key_file_lock:
        if _key_file_path is None:
            fd = tempfile.NamedTemporaryFile(
                mode="w", delete=False, prefix="evolution-ssh-", suffix=".pem"
            )
            fd.write(settings.evolution_ssh_private_key.strip() + "\n")
            fd.close()
            Path(fd.name).chmod(0o600)
            _key_file_path = fd.name
        return _key_file_path


async def _ssh(comando: str, *, timeout: float = 60.0) -> str:
    key_file = await _ssh_key_file()
    processo = await asyncio.create_subprocess_exec(
        "ssh",
        "-i",
        key_file,
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "UserKnownHostsFile=/tmp/evolution_known_hosts",
        "-o",
        "ConnectTimeout=20",
        f"{settings.evolution_ssh_user}@{settings.evolution_ssh_host}",
        comando,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(processo.communicate(), timeout=timeout)
    except TimeoutError as exc:
        processo.kill()
        raise ProvisioningError(f"ssh expirou executando: {comando[:80]}") from exc
    if processo.returncode != 0:
        raise ProvisioningError(f"ssh falhou: {stderr.decode(errors='replace')[:400]}")
    return stdout.decode(errors="replace").strip()


async def provisionar_container(
    tenant_id: str, indice: int, api_key: str, pg_senha: str, redis_senha: str
) -> None:
    """Garante que o container Evolution (+ Postgres/Redis dedicados) desta
    conexão existe e está saudável. Idempotente: se o container já existe
    (nome determinístico por tenant+índice), só espera o health check —
    nunca recria, nunca duplica.

    `pg_senha`/`redis_senha` vêm de `tenants.ensure_evolution_db_passwords`
    (achado real 24/08/2026, produto-09) -- persistidas na linha da conexão,
    não geradas aqui. Antes eram geradas a cada chamada: se Postgres/Redis já
    existiam (sobreviventes de uma tentativa interrompida) mas o Evolution
    ainda não, a senha nova não batia com a do banco já criado -- container
    em crash-loop permanente (`P1000: Authentication failed`). A linha na
    ponte agora é a fonte de verdade da senha, não a chamada."""
    n = nomes(tenant_id, indice)

    ja_existe = await _ssh(f"docker ps -aq -f name=^{n['evolution']}$")
    if not ja_existe:
        if not await _ssh(f"docker ps -aq -f name=^{n['postgres']}$"):
            await _ssh(f"mkdir -p /opt/platform/data/{n['postgres']}")
            await _ssh(
                f"docker run -d --name {n['postgres']} --restart unless-stopped "
                f"--network {settings.evolution_internal_network} "
                f"-v /opt/platform/data/{n['postgres']}:/var/lib/postgresql/data "
                f"-e POSTGRES_DB=evolution -e POSTGRES_USER=evolution "
                f"-e POSTGRES_PASSWORD='{pg_senha}' "
                f"postgres:16-alpine"
            )
        if not await _ssh(f"docker ps -aq -f name=^{n['redis']}$"):
            await _ssh(
                f"docker run -d --name {n['redis']} --restart unless-stopped "
                f"--network {settings.evolution_internal_network} "
                f"redis:7-alpine redis-server --requirepass '{redis_senha}'"
            )

        for _ in range(20):
            pronto = await _ssh(f"docker exec {n['postgres']} pg_isready -U evolution || true")
            if "accepting connections" in pronto:
                break
            await asyncio.sleep(2)
        else:
            raise ProvisioningError(f"Postgres de {tenant_id} não ficou pronto a tempo")

        db_uri = f"postgresql://evolution:{pg_senha}@{n['postgres']}:5432/evolution"
        redis_uri = f"redis://:{redis_senha}@{n['redis']}:6379/0"
        await _ssh(
            f"docker run -d --name {n['evolution']} --restart unless-stopped "
            f"--network {settings.evolution_internal_network} "
            f"-e SERVER_PORT=8080 "
            f"-e DATABASE_PROVIDER=postgresql "
            f"-e DATABASE_CONNECTION_URI='{db_uri}' "
            f"-e DATABASE_SAVE_DATA_INSTANCE=true "
            f"-e DATABASE_SAVE_DATA_NEW_MESSAGE=false "
            f"-e DATABASE_SAVE_DATA_CONTACTS=false "
            f"-e DATABASE_SAVE_DATA_CHATS=false "
            f"-e DATABASE_SAVE_DATA_LABELS=false "
            f"-e DATABASE_SAVE_DATA_HISTORIC=false "
            f"-e DATABASE_SAVE_MESSAGE_UPDATE=false "
            f"-e CACHE_REDIS_ENABLED=true -e CACHE_REDIS_URI='{redis_uri}' "
            f"-e AUTHENTICATION_API_KEY='{api_key}' "
            # Identidade de sessão (24/08/2026, pedido do dono): aparece no
            # "dispositivo conectado" do WhatsApp do cliente. Sem isso o
            # padrão da biblioteca aparece cru (mais fácil de identificar
            # como cliente não-oficial). Não resolve o sinal real de risco
            # (IP de VPS/datacenter -- já registrado como pendente,
            # precisaria de proxy residencial), só o cosmético.
            f"-e CONFIG_SESSION_PHONE_CLIENT='Windows' "
            f"-e CONFIG_SESSION_PHONE_NAME='Chrome' "
            # Confiabilidade do webhook (Evolution -> chatwoot-web): sem
            # retry configurado, uma resposta lenta do chatwoot-web (cold
            # start, deploy em andamento) descarta o evento sem tentar de
            # novo -- mensagem simplesmente não chega, sem erro visível em
            # lugar nenhum. Valores da própria documentação do Evolution.
            f"-e WEBHOOK_REQUEST_TIMEOUT_MS=60000 "
            f"-e WEBHOOK_RETRY_MAX_ATTEMPTS=10 "
            f"-e WEBHOOK_RETRY_INITIAL_DELAY_SECONDS=5 "
            # Log só do que importa -- LOG_BAILEYS=error some com o ruído
            # de protocolo (muito verboso por padrão), mantém erro real.
            f"-e LOG_LEVEL=ERROR,WARN,INFO "
            f"-e LOG_BAILEYS=error "
            f"-l traefik.enable=true "
            f"-l 'traefik.http.routers.{n['evolution']}.rule=Host(`{n['host']}`)' "
            f"-l traefik.http.routers.{n['evolution']}.entrypoints=websecure "
            f"-l traefik.http.routers.{n['evolution']}.tls.certresolver=letsencrypt "
            f"-l traefik.http.services.{n['evolution']}.loadbalancer.server.port=8080 "
            f"{settings.evolution_image}"
        )
        await _ssh(
            f"docker network connect {settings.evolution_public_network} {n['evolution']} || true"
        )

    for _ in range(40):
        saude = await _ssh(
            f"docker run --rm --network {settings.evolution_internal_network} "
            f"curlimages/curl:latest -s -o /dev/null -w '%{{http_code}}' "
            f"http://{n['evolution']}:8080/ || true"
        )
        if saude and saude[-3:] in ("200", "404"):
            return
        await asyncio.sleep(3)
    raise ProvisioningError(f"instância {n['evolution']} não respondeu ao health check")


async def remover_container(tenant_id: str, indice: int) -> None:
    n = nomes(tenant_id, indice)
    for nome in (n["evolution"], n["postgres"], n["redis"]):
        await _ssh(f"docker rm -f {nome} || true")
