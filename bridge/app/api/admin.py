"""Provisionamento e SSO.

Estas rotas são chamadas pelo agent-platform (máquina a máquina), nunca pelo
navegador de um cliente: quem provisiona conta e gera link de login é o
sistema mestre, com o token administrativo da ponte.
"""

import logging
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from app.config import settings
from app.providers import wapi
from app.services import chatwoot, tenants

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin", tags=["admin"])


def require_admin(request: Request) -> None:
    """Sem token administrativo configurado, a ponte não aceita provisionar."""
    if not settings.bridge_admin_token:
        raise HTTPException(status_code=503, detail="ponte sem token administrativo configurado")
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not secrets.compare_digest(
        token, settings.bridge_admin_token
    ):
        raise HTTPException(status_code=401, detail="não autorizado")


class TenantIn(BaseModel):
    tenant_id: str
    tenant_key: str = Field(min_length=1, max_length=100)
    tenant_name: str = Field(min_length=1, max_length=200)


class UserIn(BaseModel):
    tenant_id: str
    platform_user_id: str
    email: str
    name: str = "Operador"
    role: str = Field(default="agent", pattern="^(agent|administrator)$")


class ChannelIn(BaseModel):
    tenant_id: str
    provider: str = Field(default="wapi", pattern="^(wapi)$")
    external_id: str = Field(min_length=1, max_length=200)
    token: str | None = None
    api_base: str = "https://api.w-api.app/v1"


class AiConfigIn(BaseModel):
    tenant_id: str
    chatwoot_inbox_id: int | None = None
    template_id: str | None = None
    integration_key: str | None = None
    autopilot: bool = True
    handoff_team_id: int | None = None


@router.post("/tenants", dependencies=[Depends(require_admin)])
async def provision_tenant(payload: TenantIn):
    """Cria (ou reaproveita) a Account do Chatwoot do tenant. Idempotente."""
    link = tenants.upsert_tenant_link(
        tenant_id=payload.tenant_id,
        tenant_key=payload.tenant_key,
        tenant_name=payload.tenant_name,
    )
    if link["chatwoot_account_id"]:
        # Idempotente também para os Teams: cobre o provisionamento
        # retroativo (rodar de novo pra tenant que já existia antes desta
        # feature) e o caso comum de a Account já existir mas o admin ainda
        # não (ver _ensure_default_teams).
        await _ensure_default_teams(payload.tenant_id)
        return {
            "status": "ok",
            "chatwoot_account_id": link["chatwoot_account_id"],
            "created": False,
        }

    account = await chatwoot.create_account(payload.tenant_name)
    account_id = account.get("id")
    if not account_id:
        raise HTTPException(status_code=502, detail="Chatwoot não devolveu id da conta")
    link = tenants.set_chatwoot_account(payload.tenant_id, int(account_id))
    await _ensure_default_teams(payload.tenant_id)
    return {"status": "ok", "chatwoot_account_id": link["chatwoot_account_id"], "created": True}


async def _ensure_default_teams(tenant_id: str) -> None:
    """Cria os Teams padrão "Fila IA" e "Fila Humano" da conta, e guarda os
    dois ids na config padrão do tenant (`tenant_ai_config`, chatwoot_inbox_id
    NULL): "Fila IA" no campo novo `ai_team_id`, "Fila Humano" em
    `handoff_team_id` (já existia, usado em `_escalate`).

    Não dá pra fazer isso na criação da Account: Teams são Application API, que
    exige token de um usuário DA CONTA — e na hora que a Account nasce ainda
    não existe usuário nenhum nela (a Platform API, usada para criar a
    Account, não serve pra isso; é o mesmo motivo pelo qual o Agent Bot só é
    associado à caixa em `_garante_bot_na_caixa`, não na criação do tenant).

    Por isso este passo é best-effort e idempotente, chamado de dois lugares:
    aqui em `provision_tenant` (cobre o tenant que já tem admin quando é
    chamado de novo — inclui o provisionamento retroativo dos tenants de
    teste) e em `provision_user`, logo que o primeiro administrador ganha
    `chatwoot_user_id` (é o primeiro momento em que existe um token válido).
    Se nenhum admin existir ainda, a função não faz nada e tenta de novo na
    próxima chamada — silencioso de propósito, como o restante do
    provisionamento não-crítico desta rota.
    """
    link = tenants.get_tenant_link(tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        return

    from app.db import get_connection

    with get_connection() as conn:
        config = conn.execute(
            """SELECT ai_team_id, handoff_team_id FROM tenant_ai_config
                WHERE tenant_id = %s AND chatwoot_inbox_id IS NULL""",
            (tenant_id,),
        ).fetchone()
    ai_team_id = (config or {}).get("ai_team_id")
    humano_team_id = (config or {}).get("handoff_team_id")
    if ai_team_id and humano_team_id:
        return  # já provisionado

    admin_link = _first_admin(tenant_id)
    if admin_link is None:
        return  # sem admin ainda; a próxima chamada tenta de novo

    account_id = int(link["chatwoot_account_id"])
    try:
        token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))
        if not ai_team_id:
            time_ia = await chatwoot.create_team(account_id, token, "Fila IA")
            ai_team_id = int(time_ia["id"])
        if not humano_team_id:
            time_humano = await chatwoot.create_team(account_id, token, "Fila Humano")
            humano_team_id = int(time_humano["id"])
        tenants.set_default_teams(tenant_id, ai_team_id=ai_team_id, handoff_team_id=humano_team_id)
    except chatwoot.ChatwootError as exc:
        logger.warning("falha ao criar os Teams padrão do tenant %s: %s", tenant_id, exc)


@router.post("/users", dependencies=[Depends(require_admin)])
async def provision_user(payload: UserIn):
    """Espelha um usuário da plataforma no Chatwoot, sem pedir cadastro novo."""
    link = tenants.get_tenant_link(payload.tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        raise HTTPException(status_code=409, detail="tenant ainda não provisionado")

    user_link = tenants.upsert_user_link(
        tenant_id=payload.tenant_id,
        platform_user_id=payload.platform_user_id,
        email=payload.email,
        role=payload.role,
    )
    if user_link["chatwoot_user_id"]:
        return {"status": "ok", "chatwoot_user_id": user_link["chatwoot_user_id"], "created": False}

    # Senha aleatória: o acesso é sempre por login-link, nunca digitada. O
    # sufixo cobre a política do Chatwoot, que exige caractere especial.
    password = f"{secrets.token_urlsafe(24)}#Aa1!"
    user = await chatwoot.create_user(payload.name, payload.email, password)
    user_id = user.get("id")
    if not user_id:
        raise HTTPException(status_code=502, detail="Chatwoot não devolveu id do usuário")
    await chatwoot.add_account_user(int(link["chatwoot_account_id"]), int(user_id), payload.role)
    user_link = tenants.set_chatwoot_user(str(user_link["id"]), int(user_id))
    if payload.role == "administrator":
        # Primeiro admin com token: é o primeiro momento em que dá pra criar
        # os Teams padrão (ver _ensure_default_teams). Tenant sem admin
        # nenhum ainda fica só com a Account, sem fila — normal, é retomado
        # quando o admin for provisionado.
        await _ensure_default_teams(payload.tenant_id)
    return {"status": "ok", "chatwoot_user_id": user_link["chatwoot_user_id"], "created": True}


@router.get("/sso/{tenant_id}/{platform_user_id}", dependencies=[Depends(require_admin)])
async def sso_link(tenant_id: str, platform_user_id: str):
    """URL temporária de login no Chatwoot para um usuário já provisionado."""
    user_link = tenants.get_user_link(tenant_id, platform_user_id)
    if user_link is None or not user_link["chatwoot_user_id"]:
        raise HTTPException(status_code=404, detail="usuário não provisionado no Chatwoot")
    url = await chatwoot.login_link(int(user_link["chatwoot_user_id"]))
    return {"url": url}


@router.post("/channels", dependencies=[Depends(require_admin)])
async def provision_channel(payload: ChannelIn):
    """Registra o canal do tenant e cria a inbox de API correspondente."""
    link = tenants.get_tenant_link(payload.tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        raise HTTPException(status_code=409, detail="tenant ainda não provisionado")

    try:
        channel = tenants.upsert_channel(
            tenant_id=payload.tenant_id,
            provider=payload.provider,
            external_id=payload.external_id,
            credentials={"token": payload.token} if payload.token else None,
            api_base=payload.api_base,
        )
    except PermissionError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    if not channel["chatwoot_inbox_id"]:
        account_id = int(link["chatwoot_account_id"])
        # A inbox de API é criada com o token de um usuário administrador da
        # conta; sem nenhum usuário provisionado ainda, o passo fica pendente.
        admin_link = _first_admin(payload.tenant_id)
        if admin_link is None:
            return {
                "status": "pending_admin_user",
                "detail": "provisione um usuário administrador antes de criar a inbox",
                "webhook_path": f"/webhooks/{payload.provider}/{channel['webhook_token']}",
            }
        token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))
        # O webhook_url da inbox é a rota de saída da ponte: sem ela, o que o
        # atendente escreve no Chatwoot nunca chega ao cliente.
        outbound_url = (
            f"{settings.bridge_public_url.rstrip('/')}/outbound/{channel['webhook_token']}"
            if settings.bridge_public_url
            else ""
        )
        inbox = await chatwoot.create_api_inbox(
            account_id,
            token,
            name=f"{payload.provider}:{payload.external_id}",
            webhook_url=outbound_url,
        )
        channel = tenants.set_channel_inbox(
            str(channel["id"]), int(inbox["id"]), inbox.get("inbox_identifier")
        )

    return {
        "status": "ok",
        "channel_id": str(channel["id"]),
        "chatwoot_inbox_id": channel["chatwoot_inbox_id"],
        "webhook_path": f"/webhooks/{payload.provider}/{channel['webhook_token']}",
    }


@router.post("/channels/{channel_id}/test", dependencies=[Depends(require_admin)])
async def test_channel(channel_id: str):
    """Valida a credencial do canal sem enviar mensagem a ninguém."""
    from app.db import get_connection

    with get_connection() as conn:
        channel = conn.execute(
            "SELECT * FROM tenant_channels WHERE id = %s", (channel_id,)
        ).fetchone()
    if channel is None:
        raise HTTPException(status_code=404, detail="canal não encontrado")
    credentials = tenants.channel_credentials(channel)
    try:
        body = await wapi.check_status(credentials, channel["api_base"], channel["external_id"])
    except wapi.ProviderError as exc:
        return {"ok": False, "detail": str(exc)}
    return {"ok": True, "detail": str(body)[:300]}


@router.post("/ai-config", dependencies=[Depends(require_admin)])
async def set_ai_config(payload: AiConfigIn):
    config = tenants.upsert_ai_config(
        tenant_id=payload.tenant_id,
        chatwoot_inbox_id=payload.chatwoot_inbox_id,
        template_id=payload.template_id,
        integration_key=payload.integration_key,
        autopilot=payload.autopilot,
        handoff_team_id=payload.handoff_team_id,
    )
    bot = await _garante_bot_na_caixa(
        payload.tenant_id,
        payload.chatwoot_inbox_id,
        ligado=bool(payload.template_id and payload.autopilot),
    )
    return {
        "status": "ok",
        "autopilot": config["autopilot"],
        "has_integration_key": bool(config["integration_key_encrypted"]),
        "agent_bot": bot,
    }


async def _garante_bot_na_caixa(tenant_id: str, inbox_id: int | None, *, ligado: bool) -> str:
    """Associa (ou desassocia) o Agent Bot da conta nesta caixa.

    Escolher o agente na tela não basta: o Chatwoot só avisa a ponte de uma
    mensagem se houver um Agent Bot associado ÀQUELA caixa. A ponte fazia isso
    apenas nas caixas que ela mesma criava (W-API) — e o desenho da instalação é
    o oposto: o cliente conecta Instagram, Messenger ou WhatsApp oficial dentro
    do Chatwoot, e essas caixas nasciam sem bot. O sintoma é o pior possível:
    agente configurado, cliente escrevendo, silêncio, e nenhum erro em lugar
    nenhum.

    Falhar aqui não desfaz a configuração — ela é válida e o vínculo pode ser
    refeito. Por isso o erro vira estado devolvido, não exceção.
    """
    if inbox_id is None:
        return "sem caixa (config padrão do tenant)"

    link = tenants.get_tenant_link(tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        return "tenant sem conta no Chatwoot"
    admin_link = _first_admin(tenant_id)
    if admin_link is None:
        return "tenant sem usuário provisionado"

    account_id = int(link["chatwoot_account_id"])
    try:
        token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))
        bot_id = link["chatwoot_agent_bot_id"]
        if ligado and not bot_id:
            # Um bot por conta: o Chatwoot não deduplica por nome, e criar um a
            # cada vinculação encheria a conta de bots órfãos.
            bot = await chatwoot.create_agent_bot(
                account_id,
                name=f"IA {link['tenant_name'] or link['tenant_key']}".strip()[:60],
                outgoing_url=f"{settings.bridge_public_url.rstrip('/')}/agent-bot",
            )
            bot_id = int(bot["id"])
            tenants.set_agent_bot_id(tenant_id, bot_id)
        if ligado and bot_id:
            await chatwoot.set_agent_bot(account_id, token, inbox_id, int(bot_id))
            return "ligado"
        if not ligado and bot_id:
            await chatwoot.set_agent_bot(account_id, token, inbox_id, None)
            return "desligado"
        return "sem bot"
    except chatwoot.ChatwootError as exc:
        logger.warning("falha ao associar o Agent Bot na inbox %s: %s", inbox_id, exc)
        return f"erro: {exc}"


def _first_admin(tenant_id: str) -> dict | None:
    from app.db import get_connection

    with get_connection() as conn:
        return conn.execute(
            """SELECT * FROM user_links
                WHERE tenant_id = %s AND chatwoot_user_id IS NOT NULL
                ORDER BY (role = 'administrator') DESC, created_at
                LIMIT 1""",
            (tenant_id,),
        ).fetchone()


@router.get("/ai-config/{tenant_id}", dependencies=[Depends(require_admin)])
async def list_ai_config(tenant_id: str):
    """Caixas do tenant e qual template atende cada uma.

    Um tenant tem várias caixas — WhatsApp, Instagram, site — e cada uma pode
    ser atendida por um agente diferente. A configuração por caixa já existia no
    banco; faltava alguém conseguir ver e escolher sem chamar a API na unha.

    A lista vem do Chatwoot, não da ponte: caixa criada dentro do próprio
    Chatwoot (um Instagram conectado pela tela) não passa por aqui, e é
    exatamente onde alguém vai querer ligar a IA.
    """
    link = tenants.get_tenant_link(tenant_id)
    if link is None or not link["chatwoot_account_id"]:
        raise HTTPException(status_code=404, detail="tenant sem conta no Chatwoot")

    admin_link = _first_admin(tenant_id)
    if admin_link is None:
        raise HTTPException(status_code=409, detail="tenant sem usuário provisionado")

    token = await chatwoot.user_access_token(int(admin_link["chatwoot_user_id"]))
    caixas = await chatwoot.list_inboxes(int(link["chatwoot_account_id"]), token)

    from app.db import get_connection

    with get_connection() as conn:
        configs = conn.execute(
            "SELECT * FROM tenant_ai_config WHERE tenant_id = %s", (tenant_id,)
        ).fetchall()
    por_inbox = {c["chatwoot_inbox_id"]: c for c in configs}
    # Config com inbox NULL é o padrão do tenant: vale para caixa que ninguém
    # configurou. Mostrá-la como "herdado" evita a leitura errada de que a caixa
    # está sem IA quando ela na verdade cai no padrão.
    padrao = por_inbox.get(None)

    return {
        "default": _ai_config_out(padrao) if padrao else None,
        "inboxes": [
            {
                "chatwoot_inbox_id": int(caixa["id"]),
                "name": caixa.get("name", ""),
                "channel_type": caixa.get("channel_type", ""),
                "ai": _ai_config_out(por_inbox.get(int(caixa["id"]))),
                "inherits_default": int(caixa["id"]) not in por_inbox and padrao is not None,
            }
            for caixa in caixas
        ],
    }


def _ai_config_out(config: dict | None) -> dict | None:
    if config is None:
        return None
    return {
        "template_id": str(config["template_id"]) if config["template_id"] else None,
        "autopilot": config["autopilot"],
        "handoff_team_id": config["handoff_team_id"],
        "ai_team_id": config["ai_team_id"],
        # A chave nunca volta: o que interessa a quem lê é se existe.
        "has_integration_key": bool(config["integration_key_encrypted"]),
    }
