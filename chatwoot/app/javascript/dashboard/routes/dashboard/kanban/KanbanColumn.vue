<script setup>
import { nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import KanbanCard from './KanbanCard.vue';
import { DRAG_OPTIONS } from './dragOptions';

const props = defineProps({
  stage: { type: Object, required: true },
  stages: { type: Array, default: () => [] },
  items: { type: Array, default: () => [] },
  nextCursor: { type: String, default: null },
  loading: { type: Boolean, default: false },
  loadingMore: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
  busy: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: false },
});

const emit = defineEmits(['loadMore', 'move', 'open', 'rename', 'retry']);

const { t } = useI18n();

const localItems = ref([...props.items]);
watch(
  () => props.items,
  value => {
    localItems.value = [...value];
  }
);

// Soltar dispara 'change' (added/moved); drag cancelado nao dispara nada.
const onChange = event => {
  const info = event.added || event.moved;
  if (!info) return;
  const next = localItems.value[info.newIndex + 1];
  emit('move', {
    card: info.element,
    toStageId: props.stage.id,
    beforeCardId: next ? next.id : null,
  });
};

const onMenuMove = (card, toStageId) =>
  emit('move', { card, toStageId, beforeCardId: null });

const editing = ref(false);
const draft = ref('');
const nameInput = ref(null);

const startEdit = async () => {
  draft.value = props.stage.name;
  editing.value = true;
  await nextTick();
  nameInput.value?.focus();
};
const submitEdit = () => {
  const name = draft.value.trim();
  editing.value = false;
  if (name && name !== props.stage.name) {
    emit('rename', { id: props.stage.id, name });
  }
};
</script>

<template>
  <section
    class="flex flex-col w-72 shrink-0 max-h-full rounded-xl bg-n-alpha-1 outline outline-1 outline-n-weak"
    :aria-label="stage.name"
  >
    <header class="flex items-center gap-2 px-3 py-2">
      <span
        class="size-2.5 rounded-full shrink-0 bg-n-slate-9"
        :style="stage.color ? { backgroundColor: stage.color } : {}"
      />
      <form
        v-if="editing"
        class="flex items-center flex-1 min-w-0 gap-1"
        @submit.prevent="submitEdit"
      >
        <input
          ref="nameInput"
          v-model="draft"
          type="text"
          maxlength="60"
          class="flex-1 min-w-0 h-7 px-2 text-sm rounded bg-n-solid-2 text-n-slate-12 outline outline-1 outline-n-weak"
          :aria-label="t('KANBAN.STAGE.NAME')"
          @keydown.esc="editing = false"
        />
        <Button type="submit" xs :label="t('KANBAN.STAGE.SAVE')" />
      </form>
      <template v-else>
        <h2 class="flex-1 min-w-0 text-sm font-medium truncate text-n-slate-12">
          {{ stage.name }}
        </h2>
        <span
          class="text-xs text-n-slate-11"
          :title="t('KANBAN.STAGE.COUNT', { count: stage.count_visible })"
        >
          {{ stage.count_visible }}
        </span>
        <Button
          v-if="canEdit"
          icon="i-lucide-pencil"
          slate
          ghost
          xs
          :aria-label="t('KANBAN.STAGE.RENAME')"
          @click="startEdit"
        />
      </template>
    </header>

    <div class="flex-1 min-h-0 px-2 pb-2 overflow-y-auto">
      <div
        v-if="loading"
        class="py-6 text-xs text-center text-n-slate-11"
        role="status"
      >
        {{ t('KANBAN.LOADING') }}
      </div>
      <div v-else-if="error" class="flex flex-col items-center gap-2 py-6">
        <span class="text-xs text-n-slate-11">{{ t('KANBAN.ERROR') }}</span>
        <Button
          :label="t('KANBAN.RETRY')"
          slate
          faded
          xs
          @click="emit('retry')"
        />
      </div>
      <template v-else>
        <p
          v-if="!localItems.length"
          class="py-4 text-xs text-center text-n-slate-10"
        >
          {{ t('KANBAN.EMPTY_COLUMN') }}
        </p>
        <Draggable
          v-model="localItems"
          v-bind="DRAG_OPTIONS"
          item-key="id"
          tag="ul"
          role="list"
          class="flex flex-col gap-2 min-h-12"
          :disabled="busy"
          @change="onChange"
        >
          <template #item="{ element }">
            <li class="list-none cursor-grab">
              <KanbanCard
                :card="element"
                :stages="stages"
                :disabled="busy"
                @open="emit('open', $event)"
                @move="onMenuMove(element, $event)"
              />
            </li>
          </template>
        </Draggable>
        <div v-if="nextCursor" class="flex justify-center pt-2">
          <Button
            :label="t('KANBAN.LOAD_MORE')"
            :is-loading="loadingMore"
            slate
            faded
            xs
            @click="emit('loadMore')"
          />
        </div>
      </template>
    </div>
  </section>
</template>
