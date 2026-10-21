<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// Combo do tenant (G-4): ordem dos modelos e estratégia (fallback/rodízio). Só sugere o que o
// tenant tem; o gateway recusa provedor de outro tenant e o BFF só repassa nome, modelos e estratégia.
const props = defineProps({
  suggestions: { type: Array, default: () => [] },
  busy: { type: Boolean, default: false },
  initial: { type: Object, default: null },
});
const emit = defineEmits(['save', 'cancel']);
const { t } = useI18n();

const name = ref(props.initial?.name || '');
const models = ref([...(props.initial?.models || [])]);
const draft = ref('');
const strategy = ref(props.initial?.strategy?.fallbackStrategy || 'fallback');
const STRATEGIES = ['fallback', 'round-robin'];

const canSave = computed(() => name.value.trim() && models.value.length);

const add = () => {
  const value = draft.value.trim();
  if (!value || models.value.includes(value)) return;
  models.value.push(value);
  draft.value = '';
};
const remove = index => models.value.splice(index, 1);
const move = (index, delta) => {
  const target = index + delta;
  if (target < 0 || target >= models.value.length) return;
  const [item] = models.value.splice(index, 1);
  models.value.splice(target, 0, item);
};
const save = () =>
  emit('save', {
    name: name.value.trim(),
    models: models.value,
    strategy: { fallbackStrategy: strategy.value },
  });
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    data-testid="combo-editor"
  >
    <label class="text-body-main text-n-slate-11">
      {{ t('RAGENT.RES.FIELDS.NAME') }}
      <input
        v-model="name"
        type="text"
        class="!mb-0 w-full"
        autocomplete="off"
      />
    </label>
    <label class="text-body-main text-n-slate-11">
      {{ t('RAGENT.RES.GW.COMBO.STRATEGY') }}
      <select v-model="strategy" class="!mb-0 w-full">
        <option v-for="s in STRATEGIES" :key="s" :value="s">
          {{ t(`RAGENT.RES.GW.COMBO.${s.toUpperCase().replace('-', '_')}`) }}
        </option>
      </select>
    </label>
    <div class="flex flex-col gap-2">
      <p class="text-body-main text-n-slate-11">
        {{ t('RAGENT.RES.GW.COMBO.ORDER') }}
      </p>
      <ol class="flex flex-col gap-1">
        <li
          v-for="(m, i) in models"
          :key="m"
          class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-1"
        >
          <span class="w-6 text-n-slate-10">{{ i + 1 }}</span>
          <span class="min-w-0 flex-1 truncate text-n-slate-12">{{ m }}</span>
          <Button
            size="xs"
            variant="faded"
            label="↑"
            :disabled="i === 0"
            @click="move(i, -1)"
          />
          <Button
            size="xs"
            variant="faded"
            label="↓"
            :disabled="i === models.length - 1"
            @click="move(i, 1)"
          />
          <Button
            size="xs"
            color="ruby"
            :label="t('RAGENT.RES.DELETE')"
            @click="remove(i)"
          />
        </li>
      </ol>
      <div class="flex gap-2">
        <input
          v-model="draft"
          list="combo-suggestions"
          type="text"
          class="!mb-0 min-w-0 flex-1"
          :placeholder="t('RAGENT.RES.GW.COMBO.ADD_PLACEHOLDER')"
          @keydown.enter.prevent="add"
        />
        <datalist id="combo-suggestions">
          <option v-for="s in props.suggestions" :key="s" :value="s" />
        </datalist>
        <Button
          variant="faded"
          :label="t('RAGENT.RES.GW.COMBO.ADD')"
          @click="add"
        />
      </div>
    </div>
    <div class="flex gap-2">
      <Button
        :label="t('RAGENT.RES.SAVE')"
        :disabled="busy || !canSave"
        @click="save"
      />
      <Button
        variant="faded"
        :label="t('RAGENT.RES.GW.CANCEL')"
        @click="emit('cancel')"
      />
    </div>
  </section>
</template>
