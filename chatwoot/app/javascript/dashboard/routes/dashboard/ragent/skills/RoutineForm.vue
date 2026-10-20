<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  DEFAULT_FREQUENCY,
  TIMEZONES,
  cronFromFrequency,
  frequencyFromCron,
} from './skillText';

const props = defineProps({
  base: { type: String, required: true },
  templates: { type: Array, default: () => [] },
  // Rotina existente para editar; sem ela, cria uma nova.
  routine: { type: Object, default: null },
});
const emit = defineEmits(['saved', 'cancel']);

const { t } = useI18n();
const { axios } = window;

const CRON_EXAMPLE = '0 8 * * 1-5';
const editing = computed(() => !!props.routine);
const parsed = props.routine ? frequencyFromCron(props.routine.cron) : null;

const name = ref(props.routine?.name || '');
const instruction = ref(props.routine?.instruction || '');
// Rotinas só rodam em agentes por skills com versão publicada; os estruturados recusam o agendamento.
const routineTemplates = computed(() => {
  const skills = props.templates.filter(
    tp => tp.agent_kind === 'skills' && tp.active_version_id
  );
  return skills.length ? skills : props.templates;
});
const templateId = ref(
  props.routine?.template_id || routineTemplates.value[0]?.id || ''
);
const timezone = ref(props.routine?.timezone || 'America/Sao_Paulo');
const active = ref(props.routine ? props.routine.status === 'active' : true);
const kind = ref(
  props.routine && !parsed ? 'custom' : parsed?.kind || DEFAULT_FREQUENCY.kind
);
const frequency = ref({ ...DEFAULT_FREQUENCY, ...(parsed || {}) });
const customCron = ref(props.routine?.cron || '');
const busy = ref(false);
const error = ref('');

const zones = computed(() =>
  TIMEZONES.includes(timezone.value)
    ? TIMEZONES
    : [timezone.value, ...TIMEZONES]
);
const dayNames = computed(() => t('RAGENT.ROUTINE.DAYS').split(','));
const kinds = ['hourly', 'daily', 'weekly', 'monthly', 'custom'];

const toggleDay = day => {
  const days = frequency.value.weekdays;
  frequency.value.weekdays = days.includes(day)
    ? days.filter(d => d !== day)
    : [...days, day];
};

const preview = computed(() =>
  kind.value === 'custom'
    ? customCron.value
    : cronFromFrequency({ ...frequency.value, kind: kind.value })
);
const valid = computed(
  () =>
    name.value.trim() &&
    instruction.value.trim() &&
    templateId.value &&
    (kind.value !== 'custom' || customCron.value.trim()) &&
    (kind.value !== 'weekly' || frequency.value.weekdays.length)
);

const save = async () => {
  if (!valid.value) return;
  busy.value = true;
  error.value = '';
  const body = {
    name: name.value.trim(),
    instruction: instruction.value.trim(),
    template_id: templateId.value,
    timezone: timezone.value,
    active: active.value,
  };
  if (kind.value === 'custom') body.cron = customCron.value.trim();
  else body.frequency = { ...frequency.value, kind: kind.value };
  try {
    if (editing.value)
      await axios.put(`${props.base}/routines/${props.routine.id}`, body);
    else await axios.post(`${props.base}/routines`, body);
    useAlert(t('RAGENT.ROUTINE.SAVED'));
    emit('saved');
  } catch (err) {
    error.value = err.response?.data?.message || t('RAGENT.SKILLS.ERROR');
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <form
    class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    @submit.prevent="save"
  >
    <h2 class="text-heading-2 text-n-slate-12">
      {{
        editing ? t('RAGENT.ROUTINE.EDIT_TITLE') : t('RAGENT.ROUTINE.NEW_TITLE')
      }}
    </h2>
    <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
      {{ t('RAGENT.ROUTINE.NAME') }}
      <input v-model="name" type="text" class="!mb-0" maxlength="80" />
    </label>
    <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
      {{ t('RAGENT.ROUTINE.INSTRUCTION') }}
      <textarea
        v-model="instruction"
        rows="4"
        class="!mb-0 w-full"
        maxlength="4000"
        :placeholder="t('RAGENT.ROUTINE.INSTRUCTION_HINT')"
      />
    </label>
    <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
      {{ t('RAGENT.ROUTINE.AGENT') }}
      <select v-model="templateId" class="!mb-0">
        <option v-for="tp in routineTemplates" :key="tp.id" :value="tp.id">
          {{ tp.name }}
        </option>
      </select>
    </label>

    <div class="flex flex-wrap items-end gap-3">
      <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.ROUTINE.FREQUENCY') }}
        <select v-model="kind" class="!mb-0">
          <option v-for="k in kinds" :key="k" :value="k">
            {{ t(`RAGENT.ROUTINE.KIND.${k.toUpperCase()}`) }}
          </option>
        </select>
      </label>
      <label
        v-if="kind === 'hourly'"
        class="flex flex-col gap-1 text-body-main text-n-slate-11"
      >
        {{ t('RAGENT.ROUTINE.MINUTE') }}
        <input
          v-model.number="frequency.minute"
          type="number"
          min="0"
          max="59"
          class="!mb-0 w-24"
        />
      </label>
      <label
        v-if="['daily', 'weekly', 'monthly'].includes(kind)"
        class="flex flex-col gap-1 text-body-main text-n-slate-11"
      >
        {{ t('RAGENT.ROUTINE.TIME') }}
        <input v-model="frequency.time" type="time" class="!mb-0" />
      </label>
      <label
        v-if="kind === 'monthly'"
        class="flex flex-col gap-1 text-body-main text-n-slate-11"
      >
        {{ t('RAGENT.ROUTINE.DAY_OF_MONTH') }}
        <input
          v-model.number="frequency.day"
          type="number"
          min="1"
          max="28"
          class="!mb-0 w-24"
        />
      </label>
      <label
        v-if="kind === 'custom'"
        class="flex flex-col gap-1 text-body-main text-n-slate-11"
      >
        {{ t('RAGENT.ROUTINE.CRON') }}
        <input
          v-model="customCron"
          type="text"
          class="!mb-0 w-48 font-mono"
          :placeholder="CRON_EXAMPLE"
        />
      </label>
      <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.ROUTINE.TIMEZONE') }}
        <select v-model="timezone" class="!mb-0">
          <option v-for="z in zones" :key="z" :value="z">{{ z }}</option>
        </select>
      </label>
    </div>
    <div v-if="kind === 'weekly'" class="flex flex-wrap gap-2">
      <button
        v-for="(label, day) in dayNames"
        :key="day"
        type="button"
        class="rounded-lg border px-3 py-1 text-body-main"
        :class="
          frequency.weekdays.includes(day)
            ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
            : 'border-n-weak text-n-slate-11'
        "
        @click="toggleDay(day)"
      >
        {{ label }}
      </button>
    </div>
    <p class="text-xs text-n-slate-10">
      {{ t('RAGENT.ROUTINE.MIN_INTERVAL') }}
    </p>
    <p v-if="preview" class="text-xs text-n-slate-10">
      {{ t('RAGENT.ROUTINE.CRON_PREVIEW', { cron: preview }) }}
    </p>

    <label class="flex items-center gap-2 text-body-main text-n-slate-11">
      <input v-model="active" type="checkbox" class="!mb-0" />
      {{ t('RAGENT.ROUTINE.ACTIVE') }}
    </label>
    <p v-if="error" class="text-body-main text-n-ruby-11">{{ error }}</p>
    <div class="flex gap-2">
      <Button
        type="submit"
        size="sm"
        :label="t('RAGENT.RES.SAVE')"
        :disabled="busy || !valid"
      />
      <Button
        size="sm"
        variant="faded"
        type="button"
        :label="t('RAGENT.SKILLS.CANCEL')"
        @click="emit('cancel')"
      />
    </div>
  </form>
</template>
