import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import RtKanbanAPI from 'dashboard/api/rtKanban';
import { moveErrorKey } from './kanbanHelpers';

export const PAGE_SIZE = 30;
const MAX_LIMIT = 50;
const REFETCH_DEBOUNCE_MS = 500;
const RETRY_MS = 3000;
const DEFAULT_STATUS = 'active';
const ACTIVE_STATUSES = 'open,pending,snoozed';

const newKey = () => {
  if (window.crypto?.randomUUID) return window.crypto.randomUUID();
  const hex = n =>
    Array.from({ length: n }, () =>
      Math.floor(Math.random() * 16).toString(16)
    );
  return `${hex(8).join('')}-${hex(4).join('')}-4${hex(3).join('')}-a${hex(
    3
  ).join('')}-${hex(12).join('')}`;
};

const emptyColumn = () => ({
  items: [],
  nextCursor: null,
  loading: false,
  loadingMore: false,
  error: false,
});

export function useKanbanBoard() {
  const route = useRoute();
  const router = useRouter();
  const { t } = useI18n();

  // 'loading' | 'ready' | 'disabled' | 'error'
  const state = ref('loading');
  const board = ref(null);
  const columns = reactive({});
  const moving = ref(false);
  const lastMovedCardId = ref(null);

  const filters = computed(() => ({
    inbox_id: route.query.inbox_id || '',
    status: route.query.status || DEFAULT_STATUS,
    assignee_id: route.query.assignee_id || '',
    q: route.query.q || '',
  }));

  const cardParams = (stageId, extra = {}) => {
    const f = filters.value;
    const params = { stage_id: stageId, limit: PAGE_SIZE, ...extra };
    if (f.inbox_id) params.inbox_id = f.inbox_id;
    if (f.assignee_id) params.assignee_id = f.assignee_id;
    if (f.q) params.q = String(f.q).replace(/^#/, '').trim();
    if (f.status === 'all') params.status = 'all';
    else
      params.status = f.status === DEFAULT_STATUS ? ACTIVE_STATUSES : f.status;
    return params;
  };

  const syncColumns = stages => {
    const ids = new Set(stages.map(s => s.id));
    stages.forEach(s => {
      if (!columns[s.id]) columns[s.id] = emptyColumn();
    });
    Object.keys(columns).forEach(id => {
      if (!ids.has(Number(id))) delete columns[id];
    });
  };

  const fetchBoard = async () => {
    const { data } = await RtKanbanAPI.getBoard();
    board.value = data;
    syncColumns(data.stages || []);
    return data;
  };

  // Recarrega a primeira pagina (ou o que ja estava carregado) de uma coluna.
  const fetchColumn = async (stageId, { keepSize = false } = {}) => {
    const column = columns[stageId];
    if (!column) return;
    const limit = keepSize
      ? Math.min(MAX_LIMIT, Math.max(PAGE_SIZE, column.items.length))
      : PAGE_SIZE;
    column.loading = !keepSize || column.items.length === 0;
    column.error = false;
    try {
      const { data } = await RtKanbanAPI.getCards(
        cardParams(stageId, { limit })
      );
      column.items = data.items;
      column.nextCursor = data.next_cursor;
    } catch (error) {
      column.error = true;
    } finally {
      column.loading = false;
    }
  };

  const fetchAllColumns = (options = {}) =>
    Promise.all(
      (board.value?.stages || []).map(s => fetchColumn(s.id, options))
    );

  const load = async ({ keepSize = false } = {}) => {
    try {
      await fetchBoard();
      if (!board.value.enabled) {
        state.value = 'disabled';
        return;
      }
      state.value = 'ready';
      await fetchAllColumns({ keepSize });
    } catch (error) {
      if (error.response?.status === 404) state.value = 'disabled';
      else if (state.value === 'ready' && keepSize) {
        // refetch em segundo plano falhou (rede caiu): mantém o quadro na tela e tenta de novo
        scheduleRefetch(RETRY_MS);
      } else state.value = 'error';
    }
  };

  const loadMore = async stageId => {
    const column = columns[stageId];
    if (!column?.nextCursor || column.loadingMore) return;
    column.loadingMore = true;
    try {
      const { data } = await RtKanbanAPI.getCards(
        cardParams(stageId, { cursor: column.nextCursor })
      );
      const seen = new Set(column.items.map(c => c.id));
      column.items = [
        ...column.items,
        ...data.items.filter(c => !seen.has(c.id)),
      ];
      column.nextCursor = data.next_cursor;
    } catch (error) {
      useAlert(t('KANBAN.ERROR'));
    } finally {
      column.loadingMore = false;
    }
  };

  // Mapeia o erro da API para a mensagem do toast.
  const moveErrorMessage = error =>
    t(`KANBAN.MOVE.${moveErrorKey(error.response?.status)}`);

  /**
   * Unico caminho de movimento (drag e menu "Mover para").
   * Em erro: toast + refetch (reverte a UI otimista do drag).
   */
  const moveCard = async ({ card, toStageId, beforeCardId = null }) => {
    moving.value = true;
    try {
      const { data } = await RtKanbanAPI.moveCard(card.id, {
        to_stage_id: toStageId,
        before_card_id: beforeCardId,
        expected_lock_version: card.lock_version,
        idempotency_key: newKey(),
      });
      if (board.value) board.value.revision = data.board_revision;
      const stage = board.value?.stages.find(s => s.id === toStageId);
      useAlert(
        t('KANBAN.MOVE.DONE', {
          id: card.conversation.display_id,
          stage: stage?.name || '',
        })
      );
      lastMovedCardId.value = card.id;
      await Promise.all([fetchBoard(), fetchAllColumns({ keepSize: true })]);
      return true;
    } catch (error) {
      useAlert(moveErrorMessage(error));
      lastMovedCardId.value = card.id;
      await load({ keepSize: true });
      return false;
    } finally {
      moving.value = false;
    }
  };

  const enableBoard = async () => {
    try {
      await RtKanbanAPI.setEnabled(true);
      useAlert(t('KANBAN.ENABLED_OK'));
      state.value = 'loading';
      await load();
    } catch (error) {
      useAlert(t('KANBAN.ERROR'));
    }
  };

  const saveStage = async ({ id, name, ...rest }) => {
    try {
      if (id) await RtKanbanAPI.updateStage(id, { name, ...rest });
      else await RtKanbanAPI.createStage({ name });
      useAlert(t('KANBAN.STAGE.SAVED'));
      await fetchBoard();
      await fetchAllColumns({ keepSize: true });
      return true;
    } catch (error) {
      useAlert(t('KANBAN.STAGE.ERROR'));
      return false;
    }
  };

  const setFilter = (key, value) => {
    const query = { ...route.query };
    if (value && !(key === 'status' && value === DEFAULT_STATUS)) {
      query[key] = value;
    } else {
      delete query[key];
    }
    router.replace({ query });
  };

  // Realtime: so invalida; a lista vem sempre da API autorizada.
  let timer = null;
  function scheduleRefetch(delay = REFETCH_DEBOUNCE_MS) {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      if (moving.value) {
        scheduleRefetch();
        return;
      }
      await load({ keepSize: true });
    }, delay);
  }

  const onChanged = data => {
    if (state.value !== 'ready' && state.value !== 'disabled') return;
    const known = board.value?.revision;
    if (data?.revision != null && known != null && data.revision <= known) {
      return;
    }
    scheduleRefetch();
  };
  const onReconnect = () => scheduleRefetch();
  const onOnline = () => scheduleRefetch(0);

  onMounted(() => {
    load();
    emitter.on(BUS_EVENTS.RT_KANBAN_CHANGED, onChanged);
    emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, onReconnect);
    window.addEventListener('online', onOnline);
  });

  onBeforeUnmount(() => {
    clearTimeout(timer);
    emitter.off(BUS_EVENTS.RT_KANBAN_CHANGED, onChanged);
    emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, onReconnect);
    window.removeEventListener('online', onOnline);
  });

  watch(
    () => route.query,
    () => {
      if (state.value === 'ready') fetchAllColumns();
    }
  );

  return {
    state,
    board,
    columns,
    filters,
    moving,
    lastMovedCardId,
    load,
    loadMore,
    moveCard,
    enableBoard,
    saveStage,
    setFilter,
  };
}
