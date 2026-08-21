"""Sessão sincronizada RAgentes<->RAtende (produto-05 seção 6c).

/admin/sso já existia (gera link de login); /admin/logout é o par novo desta
frente -- login no RAgentes cria sessão real no Chatwoot, logout derruba ela.
"""

import uuid

import pytest

pytestmark = pytest.mark.integration


def _link_tenant_and_user(tenant_id: str, platform_user_id: str, chatwoot_user_id: int | None):
    from app.services import tenants

    tenants.upsert_tenant_link(tenant_id=tenant_id, tenant_key="t", tenant_name="Tenant")
    link = tenants.upsert_user_link(
        tenant_id=tenant_id, platform_user_id=platform_user_id, email="a@b.com"
    )
    if chatwoot_user_id is not None:
        tenants.set_chatwoot_user(str(link["id"]), chatwoot_user_id)


def test_sso_and_logout_require_the_shared_token(client, tenant_id):
    user_id = str(uuid.uuid4())
    assert client.get(f"/admin/sso/{tenant_id}/{user_id}").status_code == 401
    assert client.post(f"/admin/logout/{tenant_id}/{user_id}").status_code == 401


def test_logout_is_a_noop_for_a_user_never_provisioned_in_chatwoot(client, admin_auth, tenant_id):
    user_id = str(uuid.uuid4())
    _link_tenant_and_user(tenant_id, user_id, chatwoot_user_id=None)

    r = client.post(f"/admin/logout/{tenant_id}/{user_id}", headers=admin_auth)
    assert r.status_code == 200
    assert r.json() == {"status": "noop", "detail": "usuário não provisionado no Chatwoot"}


def test_logout_is_a_noop_for_an_unknown_user(client, admin_auth, tenant_id):
    user_id = str(uuid.uuid4())
    r = client.post(f"/admin/logout/{tenant_id}/{user_id}", headers=admin_auth)
    assert r.status_code == 200
    assert r.json()["status"] == "noop"


def test_logout_calls_chatwoot_for_a_provisioned_user(client, admin_auth, tenant_id, monkeypatch):
    user_id = str(uuid.uuid4())
    _link_tenant_and_user(tenant_id, user_id, chatwoot_user_id=42)

    calls = []

    async def _fake_logout_user(chatwoot_user_id):
        calls.append(chatwoot_user_id)

    from app.api import admin as admin_module

    monkeypatch.setattr(admin_module.chatwoot, "logout_user", _fake_logout_user)

    r = client.post(f"/admin/logout/{tenant_id}/{user_id}", headers=admin_auth)
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
    assert calls == [42]
