"""API interna do gateway de canais (rede interna; ver docs/canais/CONTRATO_GATEWAY.md)."""

from __future__ import annotations

import secrets
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.channels import appservice, store
from app.channels.providers.matrix_bridge import MatrixBridgeAdapter
from app.channels.provisioning import ProvisioningClient
from app.channels.service import Gateway, GatewayError, catalog
from app.config import settings

router = APIRouter(prefix="/internal/channels", tags=["channels"])
as_router = APIRouter(prefix="/_matrix/app/v1", tags=["channels-appservice"])

_gateway: Gateway | None = None


def build_default_gateway() -> Gateway:
    sender = appservice.MatrixSender()
    secret = settings.bridge_provisioning_secret
    return Gateway(
        {
            "instagram": MatrixBridgeAdapter(
                "instagram", ProvisioningClient(settings.bridge_instagram_url, secret), sender
            ),
            "messenger": MatrixBridgeAdapter(
                "messenger", ProvisioningClient(settings.bridge_messenger_url, secret), sender
            ),
            "whatsapp": MatrixBridgeAdapter(
                "whatsapp", ProvisioningClient(settings.bridge_whatsapp_url, secret), sender
            ),
        }
    )


def get_gateway() -> Gateway:
    global _gateway
    if _gateway is None:
        _gateway = build_default_gateway()
    return _gateway


def set_gateway(gw: Gateway | None) -> None:
    global _gateway
    _gateway = gw


def require_token(request: Request) -> None:
    if not settings.channels_gateway_token:
        raise HTTPException(503, "gateway sem token configurado")
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not secrets.compare_digest(
        token, settings.channels_gateway_token
    ):
        raise HTTPException(401, "nao autorizado")


def _guard(exc: GatewayError) -> HTTPException:
    return HTTPException(exc.status, exc.code)


class ConnectIn(BaseModel):
    account_id: int
    provider: str
    actor_id: str = ""
    consent: dict
    login_flow: str | None = None


class StepIn(BaseModel):
    account_id: int
    step_id: str
    kind: str
    data: dict[str, str] = {}


class AccountIn(BaseModel):
    account_id: int
    actor_id: str = ""


class DeliveryIn(BaseModel):
    account_id: int
    webhook_url: str
    webhook_secret: str
    inbox_ref: str = ""


class SendIn(BaseModel):
    account_id: int
    idempotency_key: str
    conversation_ref: str
    text: str = ""
    attachments: list[dict[str, Any]] = []
    reply_to: str | None = None


class SyncIn(BaseModel):
    account_id: int
    since_days: int = 60


@router.get("/catalog", dependencies=[Depends(require_token)])
def get_catalog():
    return catalog()


@router.post("/connections", status_code=201, dependencies=[Depends(require_token)])
async def create(body: ConnectIn, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.connect(
            account_id=body.account_id,
            provider=body.provider,
            actor_id=body.actor_id,
            consent=body.consent,
            flow=body.login_flow,
        )
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.get("/connections", dependencies=[Depends(require_token)])
def list_(account_id: int):
    from app.channels.service import public_view

    return {"connections": [public_view(r) for r in store.list_connections(account_id)]}


@router.get("/connections/{cid}", dependencies=[Depends(require_token)])
async def get_one(cid: str, account_id: int, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.status(account_id=account_id, connection_id=cid)
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.post("/connections/{cid}/step", dependencies=[Depends(require_token)])
async def step(cid: str, body: StepIn, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.step(
            account_id=body.account_id,
            connection_id=cid,
            step_id=body.step_id,
            kind=body.kind,
            data=body.data,
        )
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.post("/connections/{cid}/cancel", dependencies=[Depends(require_token)])
async def cancel(cid: str, body: AccountIn, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.cancel(account_id=body.account_id, connection_id=cid)
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.post("/connections/{cid}/disconnect", dependencies=[Depends(require_token)])
async def disconnect(cid: str, body: AccountIn, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.disconnect(
            account_id=body.account_id, connection_id=cid, actor_id=body.actor_id
        )
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.post("/connections/{cid}/revoke", dependencies=[Depends(require_token)])
async def revoke(cid: str, body: AccountIn, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.revoke(
            account_id=body.account_id, connection_id=cid, actor_id=body.actor_id
        )
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.post("/connections/{cid}/reauth", dependencies=[Depends(require_token)])
async def reauth(cid: str, body: AccountIn, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.reauth(
            account_id=body.account_id, connection_id=cid, actor_id=body.actor_id
        )
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.put("/connections/{cid}/delivery", dependencies=[Depends(require_token)])
def delivery(cid: str, body: DeliveryIn, gw: Gateway = Depends(get_gateway)):
    try:
        return gw.set_delivery(
            account_id=body.account_id,
            connection_id=cid,
            webhook_url=body.webhook_url,
            secret=body.webhook_secret,
            inbox_ref=body.inbox_ref,
        )
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.post("/connections/{cid}/send", dependencies=[Depends(require_token)])
async def send(cid: str, body: SendIn, gw: Gateway = Depends(get_gateway)):
    try:
        return await gw.send(
            account_id=body.account_id,
            connection_id=cid,
            idempotency_key=body.idempotency_key,
            conversation_ref=body.conversation_ref,
            text=body.text,
            attachments=body.attachments,
            reply_to=body.reply_to,
        )
    except GatewayError as exc:
        raise _guard(exc) from exc


@router.post("/connections/{cid}/sync", status_code=202, dependencies=[Depends(require_token)])
def sync(cid: str, body: SyncIn):
    row = store.get_connection_row(cid, body.account_id)
    if not row:
        raise HTTPException(404, "not_found")
    store.update_connection(cid, sync_status="running", sync_since_days=body.since_days)
    return {"job_id": cid, "status": "running"}


@router.get("/dead-letters", dependencies=[Depends(require_token)])
def dead(account_id: int):
    return {"items": store.dead_letters(account_id)}


@router.post("/worker/flush", dependencies=[Depends(require_token)])
async def flush(gw: Gateway = Depends(get_gateway)):
    return {**await gw.flush_webhooks(), "resent": await gw.retry_sends()}


# --- appservice (Synapse -> gateway) ----------------------------------------


@as_router.put("/transactions/{txn_id}")
async def transactions(
    txn_id: str,
    request: Request,
    access_token: str | None = None,
    gw: Gateway = Depends(get_gateway),
):
    if not appservice.verify_hs_token(access_token):
        raise HTTPException(403, "M_FORBIDDEN")
    body = await request.json()
    return await appservice.handle_transaction(gw, txn_id, body.get("events", []))
