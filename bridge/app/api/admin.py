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
    return {"status": "ok", "chatwoot_account_id": link["chatwoot_account_id"], "created": True}


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
    return {
        "status": "ok",
        "autopilot": config["autopilot"],
        "has_integration_key": bool(config["integration_key_encrypted"]),
    }


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
