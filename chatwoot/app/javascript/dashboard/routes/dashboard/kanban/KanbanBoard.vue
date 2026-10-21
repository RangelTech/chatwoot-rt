<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import KanbanColumn from './KanbanColumn.vue';
import { useKanbanBoard } from './useKanbanBoard';
import { stageAnchor } from './kanbanHelpers';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { isAdmin } = useAdmin();

const accountId = useMapGetter('getCurrentAccountId');
const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');

const {
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
} = useKanbanBoard();

onMounted(() => {
  store.dispatch('agents/get');
});

const stages = computed(() => board.value?.stages || []);

const STATUS_OPTIONS = [
  'active',
  'all',
  'open',
  'pending',
  'snoozed',
  'resolved',
];
const statusLabel = key => {
  if (key === 'active') return t('KANBAN.FILTERS.STATUS_ACTIVE');
  if (key === 'all') return t('KANBAN.FILTERS.STATUS_ALL');
  return t(`KANBAN.STATUS.${key}`);
};

const search = ref(filters.value.q);
watch(
  () => route.query.q,
  value => {
    search.value = value || '';
  }
);
const submitSearch = () => setFilter('q', search.value.trim());

// Abre a conversa pelo display_id (nunca pelo id interno).
const openCard = card => {
  router.push(
    frontendURL(
      conversationUrl({
        accountId: accountId.value,
        id: card.conversation.display_id,
      })
    )
  );
};

const focusCard = async cardId => {
  await nextTick();
  document.getElementById(`kanban-card-${cardId}`)?.focus();
};

const onMove = async payload => {
  await moveCard(payload);
  if (lastMovedCardId.value) focusCard(lastMovedCardId.value);
};

const newStageName = ref('');
const addStage = async () => {
  const name = newStageName.value.trim();
  if (!name) return;
  if (await saveStage({ name })) newStageName.value = '';
};
const renameStage = payload => saveStage(payload);

// Reordena a etapa: `direction` -1 (esquerda) ou +1 (direita); before_stage_id vazio = fim.
const reorderStage = ({ id, direction }) => {
  const anchor = stageAnchor(stages.value, id, direction);
  if (anchor === null) return;
  saveStage({ id, before_stage_id: anchor });
};

const selectClass =
  'w-auto max-w-56 h-8 px-2 text-sm rounded bg-n-alpha-1 text-n-slate-12 outline outline-1 outline-n-weak';
</script>

<template>
  <div class="flex flex-col flex-1 min-w-0 h-full gap-3 p-4 overflow-hidden">
    <div class="flex flex-wrap items-center gap-2">
      <h1 class="text-lg font-medium text-n-slate-12 me-auto">
        {{ t('KANBAN.TITLE') }}
      </h1>

      <template v-if="state === 'ready'">
        <select
          :value="filters.inbox_id"
          :class="selectClass"
          :aria-label="t('KANBAN.FILTERS.INBOX')"
          @change="setFilter('inbox_id', $event.target.value)"
        >
          <option value="">{{ t('KANBAN.FILTERS.ALL_INBOXES') }}</option>
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
            {{ inbox.name }}
          </option>
        </select>
        <select
          :value="filters.status"
          :class="selectClass"
          :aria-label="t('KANBAN.FILTERS.STATUS')"
          @change="setFilter('status', $event.target.value)"
        >
          <option v-for="key in STATUS_OPTIONS" :key="key" :value="key">
            {{ statusLabel(key) }}
          </option>
        </select>
        <select
          :value="filters.assignee_id"
          :class="selectClass"
          :aria-label="t('KANBAN.FILTERS.ASSIGNEE')"
          @change="setFilter('assignee_id', $event.target.value)"
        >
          <option value="">{{ t('KANBAN.FILTERS.ALL_ASSIGNEES') }}</option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">
            {{ agent.name }}
          </option>
        </select>
        <form class="flex" role="search" @submit.prevent="submitSearch">
          <input
            v-model="search"
            type="search"
            inputmode="numeric"
            :class="`${selectClass} !w-40`"
            :aria-label="t('KANBAN.FILTERS.SEARCH')"
            :placeholder="t('KANBAN.FILTERS.SEARCH_PLACEHOLDER')"
          />
        </form>
      </template>
    </div>

    <div
      v-if="state === 'loading'"
      class="py-10 text-sm text-center text-n-slate-11"
      role="status"
    >
      {{ t('KANBAN.LOADING') }}
    </div>

    <div
      v-else-if="state === 'error'"
      class="flex flex-col items-center gap-3 py-10"
      role="alert"
    >
      <span class="text-sm text-n-slate-11">{{ t('KANBAN.ERROR') }}</span>
      <Button :label="t('KANBAN.RETRY')" slate faded @click="load()" />
    </div>

    <div
      v-else-if="state === 'disabled'"
      class="flex flex-col items-center gap-3 py-10 text-center"
    >
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('KANBAN.DISABLED.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('KANBAN.DISABLED.DESCRIPTION') }}
      </p>
      <Button
        v-if="isAdmin"
        :label="t('KANBAN.DISABLED.ENABLE')"
        @click="enableBoard"
      />
    </div>

    <template v-else>
      <p v-if="!stages.length" class="py-6 text-sm text-center text-n-slate-11">
        {{ t('KANBAN.NO_STAGES') }}
      </p>
      <div
        class="flex flex-1 min-h-0 gap-3 pb-2 overflow-x-auto"
        :aria-busy="moving"
      >
        <KanbanColumn
          v-for="(stage, index) in stages"
          :key="stage.id"
          :stage="stage"
          :stages="stages"
          :items="columns[stage.id]?.items || []"
          :next-cursor="columns[stage.id]?.nextCursor"
          :loading="columns[stage.id]?.loading"
          :loading-more="columns[stage.id]?.loadingMore"
          :error="columns[stage.id]?.error"
          :busy="moving"
          :can-edit="isAdmin"
          :is-first="index === 0"
          :is-last="index === stages.length - 1"
          @load-more="loadMore(stage.id)"
          @move="onMove"
          @open="openCard"
          @rename="renameStage"
          @reorder="reorderStage"
          @retry="load()"
        />
        <form
          v-if="isAdmin"
          class="flex items-start w-72 gap-1 shrink-0"
          @submit.prevent="addStage"
        >
          <input
            v-model="newStageName"
            type="text"
            maxlength="60"
            :class="`${selectClass} flex-1 min-w-0`"
            :aria-label="t('KANBAN.STAGE.NAME')"
            :placeholder="t('KANBAN.STAGE.NEW_PLACEHOLDER')"
          />
          <Button
            type="submit"
            icon="i-lucide-plus"
            slate
            faded
            sm
            :aria-label="t('KANBAN.STAGE.ADD')"
          />
        </form>
      </div>
    </template>
  </div>
</template>
