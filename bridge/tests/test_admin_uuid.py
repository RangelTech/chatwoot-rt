"""Ids nao-UUID nas rotas /admin viram 422 (antes: 500 do Postgres ao comparar uuid com texto)."""
import uuid

import pytest

pytestmark = pytest.mark.integration


def test_admin_users_with_non_uuid_ids_is_422_not_500(client, admin_auth):
    body = {"tenant_id": "nao-e-uuid", "platform_user_id": "u1", "email": "a@b.com"}
    r = client.post("/admin/users", json=body, headers=admin_auth)
    assert r.status_code == 422
    body = {"tenant_id": str(uuid.uuid4()), "platform_user_id": "u1", "email": "a@b.com"}
    assert client.post("/admin/users", json=body, headers=admin_auth).status_code == 422


def test_admin_path_ids_non_uuid_are_422(client, admin_auth):
    assert client.get("/admin/sso/x/y", headers=admin_auth).status_code == 422
    assert client.post("/admin/logout/x/y", headers=admin_auth).status_code == 422
    assert client.get("/admin/ai-config/x", headers=admin_auth).status_code == 422


def test_admin_users_with_uuid_ids_still_reaches_the_tenant_check(client, admin_auth):
    body = {"tenant_id": str(uuid.uuid4()), "platform_user_id": str(uuid.uuid4()),
            "email": "a@b.com"}
    r = client.post("/admin/users", json=body, headers=admin_auth)
    assert r.status_code == 409  # tenant ainda nao provisionado
