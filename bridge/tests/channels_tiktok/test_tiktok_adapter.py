"""Adaptador TikTok + gerenciador de workers (processo real, driver fake)."""

import asyncio

import pytest
from app.channels.models import ConnectionCtx
from app.channels.providers.base import ProviderError
from app.channels.providers.tiktok import SubprocessLauncher, TikTokAdapter
from app.channels.states import State


class Sink:
    def __init__(self):
        self.messages, self.invalid, self.degraded, self.recovered = [], [], [], []

    async def on_message(self, msg):
        self.messages.append(msg)

    async def on_session_invalid(self, cid, code):
        self.invalid.append((cid, code))

    async def on_degraded(self, cid, code):
        self.degraded.append((cid, code))

    async def on_recovered(self, cid):
        self.recovered.append(cid)


def ctx(n: int, account: int = 1) -> ConnectionCtx:
    return ConnectionCtx(id=f"conn-{n}", account_id=account, provider="tiktok")


@pytest.fixture
async def adapter(tmp_path):
    sink = Sink()
    a = TikTokAdapter(SubprocessLauncher(tmp_path, "fake", qr_ttl=60), sink)
    yield a, sink, tmp_path
    for p in list(a._procs.values()):
        await p.stop()


async def _ctl(a, c, op, **args):
    return await a._procs[c.id].call("fake", {"op": op, **args})


async def _until(cond, timeout=8):
    for _ in range(int(timeout / 0.1)):
        if cond():
            return True
        await asyncio.sleep(0.1)
    return False


async def test_qr_scan_conecta_e_mensagens_nos_dois_sentidos(adapter):
    a, sink, _ = adapter
    c = ctx(1)
    v = await a.start_login(c, None)
    assert v.step.kind == "qr" and v.step.qr.data.startswith("https://fake.tiktok.test/qr/")
    assert (await a.poll_step(c)).step.kind == "qr"  # ainda esperando, mesmo QR
    await _ctl(a, c, "scan")
    done = await a.poll_step(c)
    assert done.state == State.CONNECTED and done.login_id == c.id
    await _ctl(a, c, "inbound", text="oi", id="m1", conversation="conv-1", name="Ana")
    assert await _until(lambda: len(sink.messages) == 1)
    m = sink.messages[0]
    assert m.text == "oi" and m.conversation_external_id == "conv-1" and m.contact_name == "Ana"
    ext = await a.send(c, "conv-1", "resposta", [], None)
    assert ext.startswith("sent-")
    h = await a.health(c)
    assert h.process and h.session and h.io


async def test_qr_expirado_renova_na_mesma_conexao(adapter):
    a, _, _ = adapter
    c = ctx(2)
    first = await a.start_login(c, None)
    await _ctl(a, c, "expire_qr")
    second = await a.poll_step(c)
    assert second.step.kind == "qr" and second.step.qr.data != first.step.qr.data


async def test_2fa_codigo_errado_e_certo(adapter):
    a, _, _ = adapter
    c = ctx(3)
    await a.start_login(c, None)
    await _ctl(a, c, "require_code")
    await _ctl(a, c, "scan")
    v = await a.poll_step(c)
    assert v.state == State.AWAITING_2FA and v.step.fields[0].secret
    with pytest.raises(ProviderError) as e:
        await a.submit_step(c, "tiktok.code", "code_2fa", {"verification_code": "000000"})
    assert e.value.error_code == "wrong_code"
    v = await a.submit_step(c, "tiktok.code", "code_2fa", {"verification_code": "123456"})
    assert v.state == State.CONNECTED


async def test_sessao_invalida_e_degradado_viram_eventos(adapter):
    a, sink, _ = adapter
    c = ctx(4)
    await a.start_login(c, None)
    await _ctl(a, c, "scan")
    await a.poll_step(c)
    await _ctl(a, c, "degrade")
    await _ctl(a, c, "recover")
    await _ctl(a, c, "drop")
    assert await _until(lambda: sink.invalid and sink.recovered and sink.degraded)
    assert sink.invalid[0] == (c.id, "session_invalid")


async def test_sessoes_isoladas_por_conta_e_tenant(adapter):
    a, sink, root = adapter
    c1, c2 = ctx(5, account=1), ctx(6, account=2)
    for c in (c1, c2):
        await a.start_login(c, None)
        await _ctl(a, c, "scan")
        await a.poll_step(c)
    await _ctl(a, c1, "inbound", text="so da conta 1", id="x1")
    assert await _until(lambda: len(sink.messages) == 1)
    assert sink.messages[0].connection_id == c1.id  # a segunda conta nao recebe nada
    d1, d2 = root / "1" / c1.id, root / "2" / c2.id
    assert (d1 / "session.json").exists() and (d2 / "session.json").exists()
    assert d1 != d2 and not (d2 / "history.json").exists()


async def test_logout_apaga_sessao_e_para_o_worker(adapter):
    a, _, root = adapter
    c = ctx(7)
    await a.start_login(c, None)
    await _ctl(a, c, "scan")
    await a.poll_step(c)
    sess = root / "1" / c.id / "session.json"
    assert sess.exists()
    await a.logout(c)
    assert not sess.exists() and c.id not in a._procs


async def test_restore_religa_sessao_salva(adapter):
    a, _, root = adapter
    c = ctx(8)
    await a.start_login(c, None)
    await _ctl(a, c, "scan")
    await a.poll_step(c)
    await a._procs[c.id].stop()
    assert await a.restore(c) is True
    assert (await a.health(c)).io


async def test_midia_ainda_nao_suportada(adapter):
    from app.channels.models import Attachment

    a, _, _ = adapter
    c = ctx(9)
    await a.start_login(c, None)
    await _ctl(a, c, "scan")
    await a.poll_step(c)
    with pytest.raises(ProviderError):
        await a.send(c, "conv", "", [Attachment(kind="image", url="http://x")], None)
