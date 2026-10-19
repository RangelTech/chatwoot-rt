<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  card: { type: Object, required: true },
  stages: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['open', 'move']);

const { t } = useI18n();

const conversation = computed(() => props.card.conversation || {});
const contact = computed(
  () => conversation.value.contact || t('KANBAN.CARD.NO_CONTACT')
);
const assignee = computed(
  () => conversation.value.assignee || t('KANBAN.CARD.UNASSIGNED')
);
const statusLabel = computed(() =>
  t(`KANBAN.STATUS.${conversation.value.status}`)
);
const otherStages = computed(() =>
  props.stages.filter(s => s.id !== props.card.stage_id)
);

const ariaLabel = computed(() =>
  t('KANBAN.CARD.ARIA', {
    id: conversation.value.display_id,
    contact: contact.value,
  })
);

const onMoveChange = event => {
  const toStageId = Number(event.target.value);
  // volta o select para o placeholder; a lista real vem do refetch
  // eslint-disable-next-line no-param-reassign
  event.target.value = '';
  if (toStageId) emit('move', toStageId);
};
</script>

<template>
  <div
    class="flex flex-col gap-2 p-3 bg-n-solid-2 rounded-lg outline outline-1 outline-n-weak"
  >
    <button
      :id="`kanban-card-${card.id}`"
      type="button"
      class="flex flex-col gap-1 text-start rounded focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      :aria-label="ariaLabel"
      @click="emit('open', card)"
    >
      <span class="text-sm font-medium text-n-slate-12 truncate w-full">
        {{ contact }}
      </span>
      <span class="text-xs text-n-slate-11 truncate w-full">
        #{{ conversation.display_id }} · {{ conversation.inbox }}
      </span>
      <span class="flex items-center gap-2 text-xs text-n-slate-11">
        <span class="px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-12">
          {{ statusLabel }}
        </span>
        <span class="truncate">{{ assignee }}</span>
      </span>
    </button>
    <select
      class="w-full h-8 text-xs rounded bg-n-alpha-1 text-n-slate-12 outline outline-1 outline-n-weak"
      :aria-label="t('KANBAN.MOVE.ARIA', { id: conversation.display_id })"
      :disabled="disabled"
      @change="onMoveChange"
    >
      <option value="">{{ t('KANBAN.MOVE.LABEL') }}</option>
      <option v-for="stage in otherStages" :key="stage.id" :value="stage.id">
        {{ stage.name }}
      </option>
    </select>
  </div>
</template>
