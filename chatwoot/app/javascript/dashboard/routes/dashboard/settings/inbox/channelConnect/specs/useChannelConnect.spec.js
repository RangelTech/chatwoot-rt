import { useChannelConnect, PHASES } from '../useChannelConnect';

const SECRET = 'S3nh4-Super-Secreta';

const conn = (state = 'pending_auth', extra = {}) => ({
  id: 'c1',
  state,
  ...extra,
});
const credStep = (extra = {}) => ({
  step_id: 's1',
  kind: 'credentials',
  fields: [
    { id: 'username', type: 'username', label_key: 'x' },
    { id: 'password', type: 'password', label_key: 'y', secret: true },
  ],
  ...extra,
});

const makeApi = () => ({
  start: vi.fn(),
  step: vi.fn(),
  status: vi.fn(),
  cancel: vi.fn().mockResolvedValue({}),
  reauth: vi.fn(),
  finalize: vi.fn(),
  setEntryQueue: vi.fn().mockResolvedValue({}),
});

// timers controlados: guarda a fila e executa sob demanda
const makeTimers = () => {
  const queue = [];
  return {
    queue,
    setTimer: (fn, ms) => {
      const t = { fn, ms, cleared: false };
      queue.push(t);
      return t;
    },
    clearTimer: t => {
      if (t) t.cleared = true;
    },
    async fire() {
      const t = queue.filter(q => !q.cleared).pop();
      if (!t) return false;
      t.cleared = true;
      await t.fn();
      return true;
    },
    active: () => queue.filter(q => !q.cleared),
  };
};

const setup = () => {
  const api = makeApi();
  const timers = makeTimers();
  const w = useChannelConnect({
    api,
    setTimer: timers.setTimer,
    clearTimer: timers.clearTimer,
    now: () => Date.parse('2026-10-20T12:00:00Z'),
  });
  return { api, timers, w };
};

describe('useChannelConnect', () => {
  it('exige consentimento para iniciar', async () => {
    const { api, w } = setup();
    const ok = await w.start({ provider: 'instagram', consent: false });
    expect(ok).toBe(false);
    expect(api.start).not.toHaveBeenCalled();
    expect(w.error.value.code).toBe('consent_required');
  });

  it('inicia, mostra credenciais e avanca ao 2FA e a finalizacao', async () => {
    const { api, w } = setup();
    api.start.mockResolvedValue({
      data: { connection: conn(), step: credStep() },
    });
    await w.start({ provider: 'instagram', consent: true });
    expect(api.start).toHaveBeenCalledWith({
      provider: 'instagram',
      consent: true,
      loginFlow: undefined,
    });
    expect(w.phase.value).toBe(PHASES.STEP);
    expect(w.kind.value).toBe('credentials');

    api.step.mockResolvedValue({
      data: {
        connection: conn('awaiting_2fa'),
        step: { step_id: 's2', kind: 'code_2fa', fields: [] },
      },
    });
    await w.submit('credentials', { username: 'u', password: SECRET });
    expect(api.step).toHaveBeenCalledWith('c1', {
      stepId: 's1',
      kind: 'credentials',
      data: { username: 'u', password: SECRET },
    });
    expect(w.kind.value).toBe('code_2fa');

    api.step.mockResolvedValue({
      data: {
        connection: conn('connected'),
        step: { step_id: 's3', kind: 'complete' },
      },
    });
    await w.submit('code_2fa', { code: '123456' });
    expect(w.phase.value).toBe(PHASES.FINALIZE);
  });

  it('a senha nao fica em nenhum estado exposto pelo composable', async () => {
    const { api, w } = setup();
    api.start.mockResolvedValue({
      data: { connection: conn(), step: credStep() },
    });
    await w.start({ provider: 'instagram', consent: true });
    api.step.mockResolvedValue({
      data: {
        connection: conn(),
        step: credStep({ error_code: 'wrong_password', attempts_left: 2 }),
      },
    });
    await w.submit('credentials', { username: 'u', password: SECRET });

    const snapshot = JSON.stringify({
      phase: w.phase.value,
      connection: w.connection.value,
      step: w.step.value,
      error: w.error.value,
      inbox: w.inbox.value,
    });
    expect(snapshot).not.toContain(SECRET);
    expect(JSON.stringify(Object.keys(w))).not.toContain('password');
  });

  it('erro de senha mostra attempts_left e nao tenta de novo sozinho', async () => {
    const { api, timers, w } = setup();
    api.start.mockResolvedValue({
      data: { connection: conn(), step: credStep() },
    });
    await w.start({ provider: 'instagram', consent: true });
    api.step.mockResolvedValue({
      data: {
        connection: conn(),
        step: credStep({ error_code: 'wrong_password', attempts_left: 2 }),
      },
    });
    await w.submit('credentials', { username: 'u', password: 'x' });
    expect(w.error.value).toEqual({ code: 'wrong_password', attemptsLeft: 2 });
    expect(timers.active()).toHaveLength(0);
    expect(api.step).toHaveBeenCalledTimes(1);
  });

  it('too_many_attempts trava novos envios', async () => {
    const { api, w } = setup();
    api.start.mockResolvedValue({
      data: { connection: conn(), step: credStep() },
    });
    await w.start({ provider: 'instagram', consent: true });
    api.step.mockRejectedValue({ response: { status: 429, data: {} } });
    await w.submit('credentials', { username: 'u', password: 'x' });
    expect(w.error.value.code).toBe('too_many_attempts');
    w.error.value = { code: 'too_many_attempts', attemptsLeft: 0 };
    expect(w.locked.value).toBe(true);
    api.step.mockClear();
    await w.submit('credentials', { username: 'u', password: 'x' });
    expect(api.step).not.toHaveBeenCalled();
  });

  it('await_approval faz polling no poll_after_s e cancela', async () => {
    const { api, timers, w } = setup();
    api.start.mockResolvedValue({
      data: {
        connection: conn('awaiting_challenge'),
        step: {
          step_id: 'a',
          kind: 'await_approval',
          wait: { poll_after_s: 5, can_cancel: true },
        },
      },
    });
    await w.start({ provider: 'messenger', consent: true });
    expect(timers.active()[0].ms).toBe(5000);

    api.status.mockResolvedValue({
      data: {
        connection: conn('connected'),
        step: { step_id: 'b', kind: 'complete' },
      },
    });
    await timers.fire();
    expect(api.status).toHaveBeenCalledWith('c1');
    expect(w.phase.value).toBe(PHASES.FINALIZE);
    expect(timers.active()).toHaveLength(0);
  });

  it('cancelar para o polling e chama o BFF', async () => {
    const { api, timers, w } = setup();
    api.start.mockResolvedValue({
      data: {
        connection: conn('awaiting_challenge'),
        step: { step_id: 'a', kind: 'await_approval', wait: { poll_after_s: 2 } },
      },
    });
    await w.start({ provider: 'messenger', consent: true });
    await w.cancel();
    expect(api.cancel).toHaveBeenCalledWith('c1');
    expect(w.phase.value).toBe(PHASES.CANCELLED);
    expect(timers.active()).toHaveLength(0);
  });

  it('QR renova por polling e troca o qr.data', async () => {
    const { api, timers, w } = setup();
    api.start.mockResolvedValue({
      data: {
        connection: conn(),
        step: {
          step_id: 'q',
          kind: 'qr',
          qr: {
            data: 'QR-1',
            expires_at: '2026-10-20T12:00:20Z',
            refresh_after_s: 10,
          },
        },
      },
    });
    await w.start({ provider: 'tiktok', consent: true });
    expect(w.step.value.qr.data).toBe('QR-1');
    expect(timers.active()[0].ms).toBe(10000);

    api.status.mockResolvedValue({
      data: {
        connection: conn(),
        step: {
          step_id: 'q',
          kind: 'qr',
          qr: {
            data: 'QR-2',
            expires_at: '2026-10-20T12:00:50Z',
            refresh_after_s: 10,
          },
        },
      },
    });
    await timers.fire();
    expect(w.step.value.qr.data).toBe('QR-2');
    // agenda a proxima renovacao
    expect(timers.active()).toHaveLength(1);
  });

  it('QR perto de expirar antecipa a renovacao ao tempo restante', async () => {
    const { api, timers, w } = setup();
    api.start.mockResolvedValue({
      data: {
        connection: conn(),
        step: {
          step_id: 'q',
          kind: 'qr',
          qr: {
            data: 'QR-1',
            expires_at: '2026-10-20T12:00:03Z',
            refresh_after_s: 30,
          },
        },
      },
    });
    await w.start({ provider: 'whatsapp', consent: true });
    expect(timers.active()[0].ms).toBe(3000);
  });

  it('polling desiste apos 3 falhas de rede seguidas', async () => {
    const { api, timers, w } = setup();
    api.start.mockResolvedValue({
      data: {
        connection: conn(),
        step: {
          step_id: 'q',
          kind: 'qr',
          qr: { data: 'QR', expires_at: '2026-10-20T12:01:00Z', refresh_after_s: 5 },
        },
      },
    });
    await w.start({ provider: 'tiktok', consent: true });
    api.status.mockRejectedValue(new Error('net'));
    await timers.fire();
    await timers.fire();
    await timers.fire();
    expect(api.status).toHaveBeenCalledTimes(3);
    expect(w.error.value.code).toBe('provider_unavailable');
    expect(timers.active()).toHaveLength(0);
  });

  it('syncing continua em polling ate concluir', async () => {
    const { api, timers, w } = setup();
    api.start.mockResolvedValue({
      data: {
        connection: conn('connected', { sync: { progress: 10 } }),
        step: { step_id: 'y', kind: 'syncing' },
      },
    });
    await w.start({ provider: 'instagram', consent: true });
    expect(timers.active()[0].ms).toBe(2000);
    api.status.mockResolvedValue({
      data: {
        connection: conn('connected', { sync: { progress: 100 } }),
        step: { step_id: 'z', kind: 'complete' },
      },
    });
    await timers.fire();
    expect(w.phase.value).toBe(PHASES.FINALIZE);
  });

  it('finalizar envia nome, equipe, agente e janela', async () => {
    const { api, w } = setup();
    api.start.mockResolvedValue({
      data: {
        connection: conn('connected'),
        step: { step_id: 'c', kind: 'complete' },
      },
    });
    await w.start({ provider: 'instagram', consent: true });
    api.finalize.mockResolvedValue({ data: { inbox: { id: 9 } } });
    const ok = await w.finalize({
      name: 'Caixa',
      teamId: 3,
      agentBotId: 4,
      syncSinceDays: 30,
    });
    expect(ok).toBe(true);
    expect(api.finalize).toHaveBeenCalledWith('c1', {
      name: 'Caixa',
      teamId: 3,
      agentBotId: 4,
      syncSinceDays: 30,
    });
    expect(w.phase.value).toBe(PHASES.DONE);
    expect(w.inbox.value.id).toBe(9);
    expect(api.setEntryQueue).toHaveBeenCalledWith({ inboxId: 9, teamId: 3 });
    expect(w.entryQueueFailed.value).toBe(false);
  });

  it('falha ao definir a fila de entrada nao derruba a criacao da caixa', async () => {
    const api = makeApi();
    const timers = makeTimers();
    const w = useChannelConnect({
      api,
      setTimer: timers.setTimer,
      clearTimer: timers.clearTimer,
    });
    api.start.mockResolvedValue({
      data: { connection: conn('connected'), step: { kind: 'complete' } },
    });
    await w.start({ provider: 'instagram', consent: true });
    api.finalize.mockResolvedValue({ data: { inbox: { id: 9 } } });
    api.setEntryQueue.mockRejectedValue(new Error('404'));
    const ok = await w.finalize({ name: 'C', teamId: 3, syncSinceDays: 30 });
    expect(ok).toBe(true);
    expect(w.phase.value).toBe(PHASES.DONE);
    expect(w.entryQueueFailed.value).toBe(true);
  });

  it('reauth reabre o mesmo fluxo e termina sem finalizar', async () => {
    const api = makeApi();
    const timers = makeTimers();
    const w = useChannelConnect({
      api,
      skipFinalize: true,
      setTimer: timers.setTimer,
      clearTimer: timers.clearTimer,
    });
    api.reauth.mockResolvedValue({
      data: { connection: conn('pending_auth'), step: credStep() },
    });
    await w.reauth('c1');
    expect(api.reauth).toHaveBeenCalledWith('c1');
    expect(w.kind.value).toBe('credentials');
    api.step.mockResolvedValue({
      data: {
        connection: conn('connected'),
        step: { step_id: 'k', kind: 'complete' },
      },
    });
    await w.submit('credentials', { username: 'u', password: 'p' });
    expect(w.phase.value).toBe(PHASES.DONE);
  });

  it('estado revoked/disconnected encerra o assistente', async () => {
    const { api, w } = setup();
    api.start.mockResolvedValue({
      data: { connection: conn('revoked'), step: null },
    });
    await w.start({ provider: 'instagram', consent: true });
    expect(w.phase.value).toBe(PHASES.CANCELLED);
  });
});
