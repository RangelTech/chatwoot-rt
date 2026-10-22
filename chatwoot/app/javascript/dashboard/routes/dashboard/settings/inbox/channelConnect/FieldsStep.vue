<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
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

const { t, te } = useI18n();
const values = reactive({});

const fields = computed(() => props.step.fields || []);
const isCode = computed(() => props.step.kind === 'code_2fa');
const isChoice = computed(() => props.step.kind === 'choice');
const isCaptcha = computed(() => props.step.kind === 'captcha');
const images = computed(() =>
  (props.step.attachments || []).filter(a => a.kind === 'image')
);
const audios = computed(() =>
  (props.step.attachments || []).filter(a => a.kind === 'audio')
);
const dataUrl = a => `data:${a.mime};base64,${a.data}`;

// Rotulo: traducao conhecida pelo id do campo; senao o nome que o provedor mandou.
const fieldLabel = field => {
  const key = `CHANNEL_CONNECT.FIELDS.${String(field.id).toUpperCase()}`;
  return te(key) ? t(key) : field.label || field.id;
};
const optionLabel = option => {
  const slug = String(option)
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_');
  const key = `CHANNEL_CONNECT.OPTIONS.${slug}`;
  return te(key) ? t(key) : option;
};
// Selecao ja nasce preenchida (padrao do provedor ou 1a opcao).
fields.value.forEach(f => {
  if (f.type === 'select') values[f.id] = f.default || f.options?.[0] || '';
});

const helpText = computed(() => {
  if (isCode.value) return t('CHANNEL_CONNECT.STEPS.CODE_HELP');
  if (isChoice.value) return t('CHANNEL_CONNECT.STEPS.CHOICE_HELP');
  if (isCaptcha.value) return t('CHANNEL_CONNECT.STEPS.CAPTCHA_HELP');
  return t('CHANNEL_CONNECT.STEPS.CREDENTIALS_HELP');
});
const submitLabel = computed(() => {
  if (isCode.value || isCaptcha.value) return t('CHANNEL_CONNECT.STEPS.VERIFY');
  if (isChoice.value) return t('CHANNEL_CONNECT.STEPS.CONTINUE');
  return t('CHANNEL_CONNECT.STEPS.SIGN_IN');
});
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
    data[f.id] =
      f.type === 'username' || f.type === 'select'
        ? values[f.id].trim()
        : values[f.id];
  });
  // limpa ANTES de sair do componente: so segredos; o usuario fica para a nova tentativa
  fields.value.forEach(f => {
    if (f.secret || f.type === 'password' || f.type === '2fa_code') values[f.id] = '';
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
    <p class="m-0 text-sm text-n-slate-11">{{ helpText }}</p>
    <div
      v-if="step.instructions && (isChoice || isCaptcha || isCode)"
      class="rounded-lg bg-n-alpha-2 px-3 py-2 text-xs text-n-slate-11"
      data-test="provider-message"
    >
      <span class="font-medium">
        {{ $t('CHANNEL_CONNECT.STEPS.PROVIDER_MESSAGE') }}:
      </span>
      {{ step.instructions }}
    </div>
    <div v-if="isCaptcha" class="flex flex-col gap-2" data-test="captcha">
      <img
        v-for="(a, idx) in images"
        :key="idx"
        :src="dataUrl(a)"
        :alt="$t('CHANNEL_CONNECT.STEPS.CAPTCHA_ALT')"
        class="max-w-full self-start rounded-lg border border-solid border-n-weak bg-white"
      />
      <audio
        v-for="(a, idx) in audios"
        :key="`a${idx}`"
        :src="dataUrl(a)"
        controls
        class="max-w-full"
        :aria-label="$t('CHANNEL_CONNECT.STEPS.CAPTCHA_AUDIO')"
      />
    </div>
    <label
      v-for="field in fields"
      :key="field.id"
      class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12"
    >
      {{ fieldLabel(field) }}
      <select
        v-if="field.type === 'select'"
        v-model="values[field.id]"
        :data-field="field.id"
        :disabled="busy || locked"
        class="!mb-0 w-full"
      >
        <option v-for="o in field.options" :key="o" :value="o">
          {{ optionLabel(o) }}
        </option>
      </select>
      <input
        v-else
        v-model="values[field.id]"
        :type="inputType(field)"
        :data-field="field.id"
        :inputmode="
          field.type === '2fa_code' || field.type === 'phone_number'
            ? 'numeric'
            : undefined
        "
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
    <p v-if="!isChoice" class="m-0 text-xs text-n-slate-10">
      {{ $t('CHANNEL_CONNECT.STEPS.PASSWORD_NOT_STORED') }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <NextButton
        type="submit"
        blue
        :is-loading="busy"
        :disabled="!canSubmit"
        :label="submitLabel"
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
