import { ref, computed, onBeforeUnmount, getCurrentInstance } from 'vue';
import channelConnectionsAPI from 'dashboard/api/channelConnections';
import { STEP_KINDS } from './constants';
import { isTerminalError, parseHttpError } from './errorCodes';

export const PHASES = {
  IDLE: 'idle',
  STARTING: 'starting',
  STEP: 'step',
  FINALIZE: 'finalize',
  DONE: 'done',
  CANCELLED: 'cancelled',
};

const DEFAULT_WAIT_S = 3;
const SYNC_POLL_S = 2;
const MAX_POLL_FAILURES = 3;
const MAX_BACKOFF_S = 30;

// Maquina de estados do assistente "Conectar canal".
//
// Regras de seguranca:
//  - senha e codigos entram so em submit(kind, data): vao direto ao BFF e
//    NAO sao guardados em nenhum ref/store daqui; o estado exposto guarda
//    apenas o que o gateway devolve (passo, estado, erro).
//  - sem retry automatico em erro de login: o usuario decide reenviar.
//  - polling so para passos de espera (aprovacao, QR, sync); em falha de
//    rede espera cada vez mais e desiste apos 3 falhas seguidas.
export function useChannelConnect({
  api = channelConnectionsAPI,
  setTimer = (fn, ms) => setTimeout(fn, ms),
  clearTimer = id => clearTimeout(id),
  now = () => Date.now(),
  skipFinalize = false,
} = {}) {
  const phase = ref(PHASES.IDLE);
  const connection = ref(null);
  const step = ref(null);
  const error = ref(null); // { code, attemptsLeft }
  const busy = ref(false);
  const inbox = ref(null);
  const entryQueueFailed = ref(false);

  let timer = null;
  let pollToken = 0;
  let failures = 0;

  const kind = computed(() => step.value?.kind || null);
  const locked = computed(() => !!error.value && isTerminalError(error.value.code));

  const stopPolling = () => {
    pollToken += 1;
    if (timer) clearTimer(timer);
    timer = null;
  };

  const setError = (code, attemptsLeft = null) => {
    error.value = code ? { code, attemptsLeft } : null;
  };

  const nextPollDelayMs = () => {
    const s = step.value;
    if (!s) return null;
    if (s.kind === STEP_KINDS.AWAIT_APPROVAL) {
      return (s.wait?.poll_after_s || DEFAULT_WAIT_S) * 1000;
    }
    if (s.kind === STEP_KINDS.SYNCING) return SYNC_POLL_S * 1000;
    if (s.kind === STEP_KINDS.QR || s.kind === STEP_KINDS.PAIRING_CODE) {
      const refresh = (s.qr?.refresh_after_s || DEFAULT_WAIT_S) * 1000;
      const expires = s.qr?.expires_at ? Date.parse(s.qr.expires_at) : NaN;
      // renova assim que expira (ou no intervalo sugerido, o que vier antes)
      const untilExpiry = Number.isNaN(expires) ? refresh : expires - now();
      return Math.max(1000, Math.min(refresh, untilExpiry));
    }
    return null;
  };

  const schedulePoll = (delayMs = nextPollDelayMs()) => {
    stopPolling();
    if (delayMs == null || !connection.value) return;
    const token = pollToken;
    timer = setTimer(async () => {
      if (token !== pollToken) return;
      try {
        const { data } = await api.status(connection.value.id);
        if (token !== pollToken) return;
        failures = 0;
        // eslint-disable-next-line no-use-before-define
        applyResponse(data);
      } catch (e) {
        if (token !== pollToken) return;
        failures += 1;
        if (failures >= MAX_POLL_FAILURES) {
          stopPolling();
          setError('provider_unavailable');
          return;
        }
        const wait = Math.min(
          MAX_BACKOFF_S * 1000,
          Math.max(delayMs, 1000) * 2 ** failures
        );
        schedulePoll(wait);
      }
    }, delayMs);
  };

  function applyResponse(data) {
    if (data?.connection) connection.value = data.connection;
    const nextStep = data?.step ?? null;
    step.value = nextStep;
    if (nextStep?.error_code) {
      setError(nextStep.error_code, nextStep.attempts_left ?? null);
    } else {
      setError(null);
    }

    const state = connection.value?.state;
    if (state === 'disconnected' || state === 'revoked') {
      stopPolling();
      phase.value = PHASES.CANCELLED;
      return;
    }
    if (nextStep?.kind === STEP_KINDS.COMPLETE || (!nextStep && state === 'connected')) {
      stopPolling();
      phase.value = skipFinalize ? PHASES.DONE : PHASES.FINALIZE;
      return;
    }
    phase.value = PHASES.STEP;
    if (!locked.value) schedulePoll();
    else stopPolling();
  }

  const run = async fn => {
    busy.value = true;
    try {
      const { data } = await fn();
      failures = 0;
      applyResponse(data);
      return true;
    } catch (e) {
      const parsed = parseHttpError(e);
      // erro de rede/HTTP no envio do passo: mostra, nao repete sozinho
      setError(parsed.code, parsed.attemptsLeft);
      return false;
    } finally {
      busy.value = false;
    }
  };

  const start = ({ provider, consent, loginFlow }) => {
    if (consent !== true) {
      setError('consent_required');
      return Promise.resolve(false);
    }
    phase.value = PHASES.STARTING;
    return run(() => api.start({ provider, consent, loginFlow })).then(ok => {
      if (!ok) phase.value = PHASES.IDLE;
      return ok;
    });
  };

  // Reconectar a partir de uma caixa existente (reauth_required).
  const reauth = connectionId => {
    connection.value = { id: connectionId };
    phase.value = PHASES.STARTING;
    return run(() => api.reauth(connectionId)).then(ok => {
      if (!ok) phase.value = PHASES.IDLE;
      return ok;
    });
  };

  // `data` (senha/codigo) nao e retido: so atravessa esta chamada.
  const submit = (stepKind, data) => {
    if (!connection.value || !step.value || busy.value || locked.value) {
      return Promise.resolve(false);
    }
    stopPolling();
    const stepId = step.value.step_id;
    return run(() =>
      api.step(connection.value.id, { stepId, kind: stepKind, data })
    );
  };

  const cancel = async () => {
    stopPolling();
    if (!connection.value?.id) {
      phase.value = PHASES.CANCELLED;
      return;
    }
    try {
      await api.cancel(connection.value.id);
    } catch (e) {
      // cancelar e melhor-esforco; o gateway expira o login sozinho
    }
    phase.value = PHASES.CANCELLED;
  };

  const finalize = async ({ name, teamId, agentBotId, syncSinceDays }) => {
    busy.value = true;
    try {
      const { data } = await api.finalize(connection.value.id, {
        name,
        teamId,
        agentBotId,
        syncSinceDays,
      });
      inbox.value = data.inbox || data;
      if (teamId && inbox.value?.id) {
        try {
          await api.setEntryQueue({ inboxId: inbox.value.id, teamId });
        } catch (e) {
          // fila de entrada e melhor-esforco: a caixa fica no modo legado
          // e o usuario ajusta depois em Atendimento.
          entryQueueFailed.value = true;
        }
      }
      phase.value = PHASES.DONE;
      setError(null);
      return true;
    } catch (e) {
      setError(parseHttpError(e).code);
      return false;
    } finally {
      busy.value = false;
    }
  };

  // Retoma o polling manualmente depois de uma falha de rede.
  const resumePolling = () => {
    failures = 0;
    setError(null);
    schedulePoll(1000);
  };

  if (getCurrentInstance()) onBeforeUnmount(stopPolling);

  return {
    phase,
    connection,
    step,
    kind,
    error,
    busy,
    inbox,
    entryQueueFailed,
    locked,
    start,
    reauth,
    submit,
    cancel,
    finalize,
    resumePolling,
    stopPolling,
  };
}
