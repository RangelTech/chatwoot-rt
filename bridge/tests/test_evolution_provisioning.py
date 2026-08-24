"""Produto-05 seção 4 — QR automático: a ponte deriva o tenant pela conta do
Chatwoot (nunca aceita tenant_id do chamador), nunca duplica container numa
segunda chamada, e nunca deixa o admin de um tenant provisionar/ver a
instância de outro."""

import pytest

pytestmark = pytest.mark.integration


def _link_tenant(tenant_id: str, account_id: int) -> None:
    from app.services import tenants

    tenants.upsert_tenant_link(tenant_id=tenant_id, tenant_key="t", tenant_name="Tenant")
    tenants.set_chatwoot_account(tenant_id, account_id)


def test_conta_sem_tenant_vinculado_eh_rejeitada(client, admin_auth):
    r = client.post(
        "/admin/evolution/provision",
        json={"chatwoot_account_id": 424242},
        headers=admin_auth,
    )
    assert r.status_code == 404


def test_provisiona_uma_vez_e_reaproveita_na_segunda_chamada(
    client, admin_auth, tenant_id, monkeypatch
):
    from app.services import evolution

    chamadas = []

    async def fake_provisionar_container(tenant, indice, api_key, pg_senha, redis_senha):
        chamadas.append((tenant, indice, api_key, pg_senha, redis_senha))

    monkeypatch.setattr(evolution, "provisionar_container", fake_provisionar_container)
    _link_tenant(tenant_id, account_id=501)

    r1 = client.post(
        "/admin/evolution/provision",
        json={"chatwoot_account_id": 501},
        headers=admin_auth,
    )
    assert r1.status_code == 200
    corpo1 = r1.json()
    assert corpo1["status"] == "ready"
    assert corpo1["instance_name"]
    assert corpo1["api_key"]

    r2 = client.post(
        "/admin/evolution/provision",
        json={"chatwoot_account_id": 501},
        headers=admin_auth,
    )
    corpo2 = r2.json()

    # Mesma instância, mesma chave -- nada foi recriado.
    assert corpo2["instance_name"] == corpo1["instance_name"]
    assert corpo2["api_key"] == corpo1["api_key"]
    assert len(chamadas) == 1


def test_dois_tenants_geram_instancias_diferentes_e_isoladas(client, admin_auth, monkeypatch):
    import uuid

    from app.services import evolution

    async def fake_provisionar_container(tenant, indice, api_key, pg_senha, redis_senha):
        return None

    monkeypatch.setattr(evolution, "provisionar_container", fake_provisionar_container)

    tenant_a, tenant_b = str(uuid.uuid4()), str(uuid.uuid4())
    _link_tenant(tenant_a, account_id=601)
    _link_tenant(tenant_b, account_id=602)

    ra = client.post(
        "/admin/evolution/provision", json={"chatwoot_account_id": 601}, headers=admin_auth
    ).json()
    rb = client.post(
        "/admin/evolution/provision", json={"chatwoot_account_id": 602}, headers=admin_auth
    ).json()

    assert ra["instance_name"] != rb["instance_name"]
    assert ra["api_key"] != rb["api_key"]


def test_falha_no_provisionamento_marca_a_conexao_como_failed_e_devolve_502(
    client, admin_auth, tenant_id, monkeypatch
):
    from app.services import evolution, tenants

    async def fake_falha(tenant, indice, api_key, pg_senha, redis_senha):
        raise evolution.ProvisioningError("instância não respondeu ao health check")

    monkeypatch.setattr(evolution, "provisionar_container", fake_falha)
    _link_tenant(tenant_id, account_id=701)

    r = client.post(
        "/admin/evolution/provision", json={"chatwoot_account_id": 701}, headers=admin_auth
    )
    assert r.status_code == 502
    assert tenants.get_evolution_connection(tenant_id)["status"] == "failed"


# Achado real 24/08/2026 (produto-09 seção 5): esta rota não existia --
# apagar a inbox no Chatwoot nunca desligava a instância real, reconectar
# reaproveitava a mesma sessão WhatsApp já logada em vez de gerar QR novo.


def test_deprovision_remove_container_e_a_linha_da_ponte(
    client, admin_auth, tenant_id, monkeypatch
):
    from app.services import evolution, tenants

    async def fake_provisionar_container(tenant, indice, api_key, pg_senha, redis_senha):
        return None

    chamadas_remocao = []

    async def fake_remover_container(tenant, indice):
        chamadas_remocao.append((tenant, indice))

    monkeypatch.setattr(evolution, "provisionar_container", fake_provisionar_container)
    monkeypatch.setattr(evolution, "remover_container", fake_remover_container)
    _link_tenant(tenant_id, account_id=801)

    provisionado = client.post(
        "/admin/evolution/provision", json={"chatwoot_account_id": 801}, headers=admin_auth
    ).json()

    r = client.post(
        "/admin/evolution/deprovision",
        json={"chatwoot_account_id": 801, "instance_name": provisionado["instance_name"]},
        headers=admin_auth,
    )

    assert r.status_code == 200
    assert r.json()["status"] == "removed"
    assert chamadas_remocao == [(tenant_id, 1)]
    assert tenants.get_evolution_connection(tenant_id) is None


def test_deprovision_de_instancia_inexistente_eh_um_no_op(client, admin_auth, tenant_id):
    _link_tenant(tenant_id, account_id=802)

    r = client.post(
        "/admin/evolution/deprovision",
        json={"chatwoot_account_id": 802, "instance_name": "evolution-nunca-existiu"},
        headers=admin_auth,
    )

    assert r.status_code == 200
    assert r.json()["status"] == "not_found"


def test_deprovision_de_conta_sem_tenant_vinculado_eh_rejeitada(client, admin_auth):
    r = client.post(
        "/admin/evolution/deprovision",
        json={"chatwoot_account_id": 424242, "instance_name": "evolution-x"},
        headers=admin_auth,
    )
    assert r.status_code == 404
