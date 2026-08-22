"""Provisiona a instância dedicada de Evolution API de um tenant (produto-05
seção 4).

Por que dedicada e não compartilhada: a Evolution API não tem clustering nem
failover entre réplicas (`waInstances` vive em memória de um processo só), e
há bug real documentado (issue upstream #1687) onde criar uma instância nova
pode derrubar instância existente não-relacionada no MESMO processo — risco
direto pra multi-tenant. Com 1 container por tenant, o bug fica sequer
aplicável (não existe "outra instância no mesmo processo" pra derrubar) e o
raio de explosão de uma queda fica contido a 1 cliente.

Postgres e Redis também são dedicados — não só ao resto do stack, mas entre
os próprios containers Evolution (achado de auditoria da spec, seção 4):
issue #652 mostra que instabilidade do Redis trava a Evolution inteira
("always loading"), então um Redis único compartilhado recriaria o mesmo
raio de explosão que o sharding por container foi desenhado pra eliminar.

O que este script faz, em ordem:
  1. cria Postgres+Redis dedicados do tenant (containers próprios, rede
     interna only, nunca expostos);
  2. cria o container Evolution, publicado no Traefik via label dinâmica
     (Host baseado no wildcard *.evolution.rangeltech.net, sem precisar de
     DNS novo);
  3. espera o health check responder;
  4. registra o canal no Chatwoot (Channel::EvolutionApi) via Application
     API, criando a inbox se ainda não existir.

Um tenant pode ter mais de 1 conexão Evolution (ex. 2 números de WhatsApp
não-oficial) -- cada uma com --indice diferente, cada uma com seu próprio
container/Postgres/Redis/subdomínio, nunca compartilhados entre si (mesmo
motivo do isolamento por tenant: 2 instâncias no mesmo processo reintroduz
o bug #1687, mesmo sendo do mesmo cliente).

Uso:
    python scripts/provisionar_evolution.py <tenant_id> <account_id>
    python scripts/provisionar_evolution.py <tenant_id> <account_id> --indice 2
    python scripts/provisionar_evolution.py <tenant_id> <account_id> --remover [--indice N]
"""

import argparse
import json
import os
import secrets
import subprocess
import sys
import time

import httpx

VPS_HOST = os.environ.get("EVOLUTION_VPS_HOST", "66.94.101.153")
VPS_USER = os.environ.get("EVOLUTION_VPS_USER", "deploy")
SSH_KEY = os.environ.get("EVOLUTION_SSH_KEY", os.path.expanduser("~/.ssh/vps_rt_infra_ed25519_v2"))
DOMINIO = os.environ.get("EVOLUTION_DOMAIN", "evolution.rangeltech.net")
IMAGEM = os.environ.get("EVOLUTION_IMAGE", "evoapicloud/evolution-api:v2.3.7")
REDE_INTERNA = os.environ.get("EVOLUTION_INTERNAL_NETWORK", "internal")
REDE_PUBLICA = os.environ.get("EVOLUTION_PUBLIC_NETWORK", "public")

CHATWOOT_BASE_URL = os.environ.get("CHATWOOT_BASE_URL", "https://chat.rangeltech.net")
CHATWOOT_PLATFORM_TOKEN = os.environ.get("CHATWOOT_PLATFORM_TOKEN", "")


def ssh(comando: str) -> str:
    resultado = subprocess.run(
        ["ssh", "-i", SSH_KEY, "-o", "ConnectTimeout=25", f"{VPS_USER}@{VPS_HOST}", comando],
        capture_output=True,
        text=True,
    )
    if resultado.returncode != 0:
        raise RuntimeError(f"ssh falhou: {resultado.stderr[:400]}")
    return resultado.stdout.strip()


def nomes(tenant_id: str, indice: int = 1) -> dict:
    """indice=1 é a 1ª conexão do tenant (sufixo vazio, compatível com
    instâncias já provisionadas antes desta função existir). indice>=2 é
    uma conexão adicional -- container, Postgres, Redis e subdomínio TODOS
    dedicados de novo, nunca compartilhados entre conexões do mesmo tenant
    (mesmo motivo de sempre: 2 instâncias Evolution no mesmo processo
    reintroduz o bug #1687, mesmo sendo do mesmo cliente)."""
    curto = tenant_id.replace("-", "")[:12]
    sufixo = "" if indice <= 1 else f"-{indice}"
    return {
        "evolution": f"evolution-{curto}{sufixo}",
        "postgres": f"evolution-pg-{curto}{sufixo}",
        "redis": f"evolution-redis-{curto}{sufixo}",
        "host": f"evolution-{curto}{sufixo}.{DOMINIO}",
    }


def provisionar(tenant_id: str, account_id: str, indice: int = 1) -> dict:
    n = nomes(tenant_id, indice)
    pg_senha = secrets.token_urlsafe(24)
    redis_senha = secrets.token_urlsafe(24)
    api_key = secrets.token_urlsafe(24)

    existente = ssh(f"docker ps -aq -f name=^{n['evolution']}$")
    if existente:
        raise SystemExit(f"instância {n['evolution']} já existe — remova antes de recriar")

    # 1. Postgres dedicado -- rede interna only, nunca publicado.
    ssh(f"mkdir -p /opt/platform/data/{n['postgres']}")
    ssh(
        f"docker run -d --name {n['postgres']} --restart unless-stopped "
        f"--network {REDE_INTERNA} "
        f"-v /opt/platform/data/{n['postgres']}:/var/lib/postgresql/data "
        f"-e POSTGRES_DB=evolution -e POSTGRES_USER=evolution "
        f"-e POSTGRES_PASSWORD='{pg_senha}' "
        f"postgres:16-alpine"
    )

    # 2. Redis dedicado -- idem, mesmo motivo (achado de auditoria seção 4).
    ssh(
        f"docker run -d --name {n['redis']} --restart unless-stopped "
        f"--network {REDE_INTERNA} "
        f"redis:7-alpine redis-server --requirepass '{redis_senha}'"
    )

    # Postgres precisa estar de pé antes da Evolution tentar migrar o schema.
    for _ in range(20):
        pronto = ssh(f"docker exec {n['postgres']} pg_isready -U evolution || true")
        if "accepting connections" in pronto:
            break
        time.sleep(2)
    else:
        raise SystemExit(f"Postgres de {tenant_id} não ficou pronto a tempo")

    # 3. Evolution -- conecta nas duas redes: interna (Postgres/Redis) e
    # pública (Traefik). DATABASE_SAVE_DATA_* mínimo: só a sessão/credencial
    # do Baileys persiste (INSTANCE), não o histórico completo -- o Chatwoot
    # já é o sistema de registro de verdade (achado seção 4, evita duplicar
    # dado em N schemas).
    db_uri = f"postgresql://evolution:{pg_senha}@{n['postgres']}:5432/evolution"
    redis_uri = f"redis://:{redis_senha}@{n['redis']}:6379/0"
    ssh(
        f"docker run -d --name {n['evolution']} --restart unless-stopped "
        f"--network {REDE_INTERNA} "
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
        f"-l traefik.enable=true "
        f"-l 'traefik.http.routers.{n['evolution']}.rule=Host(`{n['host']}`)' "
        f"-l traefik.http.routers.{n['evolution']}.entrypoints=websecure "
        f"-l traefik.http.routers.{n['evolution']}.tls.certresolver=letsencrypt "
        f"-l traefik.http.services.{n['evolution']}.loadbalancer.server.port=8080 "
        f"{IMAGEM}"
    )
    ssh(f"docker network connect {REDE_PUBLICA} {n['evolution']} || true")

    for _ in range(40):
        saude = ssh(
            f"docker run --rm --network {REDE_INTERNA} curlimages/curl:latest -s -o /dev/null "
            f"-w '%{{http_code}}' http://{n['evolution']}:8080/ || true"
        )
        if saude and saude[-3:] in ("200", "404"):
            # Evolution responde 404 na raiz mesmo saudável (não tem rota lá);
            # o que importa é que o processo já aceita conexão HTTP.
            break
        time.sleep(3)
    else:
        raise SystemExit(f"instância {n['evolution']} não respondeu ao health check")

    return {
        "evolution_container": n["evolution"],
        "instance_name": n["evolution"],
        "api_url": f"https://{n['host']}",
        "api_key": api_key,
        "indice": indice,
    }


def registrar_no_chatwoot(account_id: str, dados: dict) -> dict:
    """Cria a inbox Channel::EvolutionApi no Chatwoot, se ainda não existir."""
    if not CHATWOOT_PLATFORM_TOKEN:
        print("AVISO: CHATWOOT_PLATFORM_TOKEN ausente -- pulei o registro no Chatwoot")
        return {}

    with httpx.Client(base_url=CHATWOOT_BASE_URL, timeout=60.0) as client:
        admin = client.get(
            f"/platform/api/v1/accounts/{account_id}/account_users",
            headers={"api_access_token": CHATWOOT_PLATFORM_TOKEN},
        ).json()
        admin_user = next(
            (u for u in admin if u.get("role") == "administrator"), admin[0] if admin else None
        )
        if admin_user is None:
            raise SystemExit(f"conta {account_id} não tem nenhum usuário provisionado")
        user = client.get(
            f"/platform/api/v1/users/{admin_user['user_id']}",
            headers={"api_access_token": CHATWOOT_PLATFORM_TOKEN},
        ).json()
        access_token = user["access_token"]

        rotulo = f" {dados['indice']}" if dados["indice"] > 1 else ""
        resposta = client.post(
            f"/api/v1/accounts/{account_id}/inboxes",
            headers={"api_access_token": access_token},
            json={
                "name": f"WhatsApp (Evolution){rotulo}",
                "channel": {
                    "type": "evolution_api",
                    "instance_name": dados["instance_name"],
                    "api_url": dados["api_url"],
                    "api_key": dados["api_key"],
                },
            },
        )
        resposta.raise_for_status()
        return resposta.json()


def remover(tenant_id: str, indice: int = 1) -> None:
    n = nomes(tenant_id, indice)
    for nome in (n["evolution"], n["postgres"], n["redis"]):
        ssh(f"docker rm -f {nome} || true")
    print(f"containers de {tenant_id} (conexão {indice}) removidos (volumes preservados em /opt/platform/data)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tenant_id")
    parser.add_argument("account_id")
    parser.add_argument(
        "--indice",
        type=int,
        default=1,
        help="qual conexão Evolution deste tenant (1=primeira, sem sufixo; "
        "2, 3... = conexões adicionais, cada uma com container/Postgres/"
        "Redis/subdomínio próprios, nunca compartilhados)",
    )
    parser.add_argument("--remover", action="store_true")
    args = parser.parse_args()

    if args.remover:
        remover(args.tenant_id, args.indice)
        return

    dados = provisionar(args.tenant_id, args.account_id, args.indice)
    inbox = registrar_no_chatwoot(args.account_id, dados)
    print(json.dumps({**dados, "inbox": inbox}, indent=2))
    print("instância Evolution provisionada")


if __name__ == "__main__":
    sys.exit(main())
