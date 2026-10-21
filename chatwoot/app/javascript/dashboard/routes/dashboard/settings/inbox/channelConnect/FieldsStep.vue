<script setup>
import { reactive, computed } from 'vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

// Passo "credentials" e "code_2fa". Senha e codigo vivem so neste estado
// local: sao enviados via evento e apagados na mesma hora. Nada vai para
// Vuex, localStorage, props ou URL.
const props = defineProps({
  step: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  locked: { type: Boolean, default: false },
});
const emit = defineEmits(['submit', 'cancel']);

const values = reactive({});

const fields = computed(() => props.step.fields || []);
const isCode = computed(() => props.step.kind === 'code_2fa');
const canSubmit = computed(
  () =>
    !props.busy &&
    !props.locked &&
    fields.value.length > 0 &&
    fields.value.every(f => (values[f.id] || '').trim().length > 0)
);

const inputType = field => {
  if (field.secret || field.type === 'password') return 'password';
  return 'text';
};

const onSubmit = () => {
  if (!canSubmit.value) return;
  const data = {};
  fields.value.forEach(f => {
    data[f.id] = f.type === 'username' ? values[f.id].trim() : values[f.id];
  });
  // limpa ANTES de sair do componente
  Object.keys(values).forEach(k => {
    values[k] = '';
  });
  emit('submit', data);
};
</script>

<template>
  <form
    autocomplete="off"
    class="flex flex-col gap-5"
    data-test="fields-step"
    @submit.prevent="onSubmit"
  >
    <p class="m-0 text-sm text-n-slate-11">
      {{
        isCode
          ? $t('CHANNEL_CONNECT.STEPS.CODE_HELP')
          : $t('CHANNEL_CONNECT.STEPS.CREDENTIALS_HELP')
      }}
    </p>
    <label
      v-for="field in fields"
      :key="field.id"
      class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12"
    >
      {{ $t(field.label_key) }}
      <input
        v-model="values[field.id]"
        :type="inputType(field)"
        :data-field="field.id"
        :inputmode="field.type === '2fa_code' ? 'numeric' : undefined"
        :maxlength="field.type === '2fa_code' ? 10 : undefined"
        autocomplete="off"
        autocapitalize="off"
        spellcheck="false"
        data-1p-ignore
        data-lpignore="true"
        :disabled="busy || locked"
        class="!mb-0 w-full"
      />
    </label>
    <p class="m-0 text-xs text-n-slate-10">
      {{ $t('CHANNEL_CONNECT.STEPS.PASSWORD_NOT_STORED') }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <NextButton
        type="submit"
        blue
        :is-loading="busy"
        :disabled="!canSubmit"
        :label="
          isCode
            ? $t('CHANNEL_CONNECT.STEPS.VERIFY')
            : $t('CHANNEL_CONNECT.STEPS.SIGN_IN')
        "
      />
      <NextButton
        type="button"
        variant="ghost"
        color="slate"
        :label="$t('CHANNEL_CONNECT.ACTIONS.CANCEL')"
        @click="emit('cancel')"
      />
    </div>
  </form>
</template>
