<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { PROVIDERS, STEP_KINDS } from './constants';
import { useChannelConnect, PHASES } from './useChannelConnect';
import ErrorNotice from './ErrorNotice.vue';
import FieldsStep from './FieldsStep.vue';
import WaitStep from './WaitStep.vue';
import QrStep from './QrStep.vue';
import SyncStep from './SyncStep.vue';
import FinalizeStep from './FinalizeStep.vue';

const props = defineProps({
  provider: { type: String, required: true },
  // reconectar: id da conexao existente (pula escolha Oficial x Experimental)
  reauthConnectionId: { type: [String, Number], default: null },
});
const emit = defineEmits(['done', 'close']);

const store = useStore();
const router = useRouter();
const { accountId } = useAccount();

const meta = computed(() => PROVIDERS[props.provider]);
const mode = ref(props.reauthConnectionId ? 'experimental' : null);
const consent = ref(false);

const wizard = useChannelConnect({ skipFinalize: !!props.reauthConnectionId });
const { phase, step, kind, error, busy, locked, connection } = wizard;

const titleKey = computed(
  () => `CHANNEL_CONNECT.PROVIDERS.${props.provider.toUpperCase()}`
);
const waiting = computed(() => kind.value === STEP_KINDS.AWAIT_APPROVAL);
const isFields = computed(() =>
  [STEP_KINDS.CREDENTIALS, STEP_KINDS.CODE_2FA].includes(kind.value)
);
const isQr = computed(() =>
  [STEP_KINDS.QR, STEP_KINDS.PAIRING_CODE].includes(kind.value)
);

const goOfficial = () => {
  router.push({
    name: 'settings_inboxes_page_channel',
    params: {
      sub_page: meta.value.officialSubPage,
      accountId: accountId.value,
    },
  });
};

const begin = () => {
  if (!consent.value) return;
  wizard.start({ provider: props.provider, consent: consent.value });
};

const onSubmitFields = data => wizard.submit(kind.value, data);

const onFinalize = async payload => {
  const ok = await wizard.finalize(payload);
  if (!ok) return;
  store.dispatch('inboxes/get');
  emit('done', wizard.inbox.value);
  const id = wizard.inbox.value?.id;
  if (id) {
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: id },
    });
  }
};

const close = async () => {
  if (phase.value === PHASES.STEP) await wizard.cancel();
  emit('close');
  if (!props.reauthConnectionId) {
    router.push({
      name: 'settings_inbox_new',
      params: { accountId: accountId.value },
    });
  }
};

onMounted(() => {
  store.dispatch('teams/get');
  store.dispatch('agentBots/get');
  if (props.reauthConnectionId) {
    wizard.reauth(props.reauthConnectionId);
  }
});

defineExpose({ wizard });
</script>

<template>
  <div class="w-full max-w-xl" data-test="connect-wizard">
    <div class="mb-6 flex items-center gap-3">
      <div
        class="flex size-10 items-center justify-center rounded-full bg-n-alpha-2"
      >
        <Icon :icon="meta.icon" class="size-6 text-n-slate-10" />
      </div>
      <div>
        <h2 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ $t(titleKey) }}
        </h2>
        <p class="m-0 text-xs text-n-slate-10">
          {{ $t('CHANNEL_CONNECT.EXPERIMENTAL_BADGE') }}
        </p>
      </div>
    </div>

    <!-- 1. Oficial x Experimental -->
    <div
      v-if="!mode"
      class="grid grid-cols-1 gap-4 sm:grid-cols-2"
      data-test="mode-choice"
    >
      <button
        type="button"
        class="flex flex-col items-start gap-2 rounded-2xl border border-solid border-n-weak bg-n-solid-1 p-5 text-start transition hover:border-n-blue-9 hover:shadow-md"
        data-test="mode-official"
        @click="goOfficial"
      >
        <span class="text-base font-medium text-n-slate-12">
          {{ $t('CHANNEL_CONNECT.MODE.OFFICIAL_TITLE') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ $t('CHANNEL_CONNECT.MODE.OFFICIAL_DESC') }}
        </span>
      </button>
      <button
        type="button"
        class="flex flex-col items-start gap-2 rounded-2xl border border-solid border-n-amber-7 bg-n-solid-1 p-5 text-start transition hover:border-n-amber-9 hover:shadow-md"
        data-test="mode-experimental"
        @click="mode = 'experimental'"
      >
        <span class="text-base font-medium text-n-slate-12">
          {{ $t('CHANNEL_CONNECT.MODE.EXPERIMENTAL_TITLE') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ $t('CHANNEL_CONNECT.MODE.EXPERIMENTAL_DESC') }}
        </span>
      </button>
    </div>

    <!-- 2. Requisitos, riscos e consentimento -->
    <div
      v-else-if="phase === PHASES.IDLE || phase === PHASES.STARTING"
      class="flex flex-col gap-5"
      data-test="consent-step"
    >
      <section
        class="rounded-2xl border border-solid border-n-weak bg-n-solid-1 p-5"
      >
        <h3 class="m-0 mb-2 text-sm font-semibold text-n-slate-12">
          {{ $t('CHANNEL_CONNECT.INFO.REQUIREMENTS_TITLE') }}
        </h3>
        <ul class="m-0 ps-5 text-sm text-n-slate-11">
          <li>
            {{
              $t(
                `CHANNEL_CONNECT.INFO.REQUIREMENTS_${meta.login.toUpperCase()}`
              )
            }}
          </li>
        </ul>
        <h3 class="m-0 mb-2 mt-4 text-sm font-semibold text-n-slate-12">
          {{ $t('CHANNEL_CONNECT.INFO.LIMITATIONS_TITLE') }}
        </h3>
        <ul class="m-0 ps-5 text-sm text-n-slate-11">
          <li>{{ $t('CHANNEL_CONNECT.INFO.LIMITATIONS_TEXT') }}</li>
          <li>{{ $t('CHANNEL_CONNECT.INFO.LIMITATIONS_MEDIA') }}</li>
        </ul>
      </section>
      <section
        class="rounded-2xl border border-solid border-n-amber-7 bg-n-amber-3 p-5 text-n-amber-11"
        data-test="risk-box"
      >
        <h3 class="m-0 mb-2 flex items-center gap-2 text-sm font-semibold">
          <Icon icon="i-lucide-triangle-alert" class="size-4" />
          {{ $t('CHANNEL_CONNECT.INFO.RISKS_TITLE') }}
        </h3>
        <ul class="m-0 ps-5 text-sm">
          <li>{{ $t('CHANNEL_CONNECT.INFO.RISK_BLOCK') }}</li>
          <li>{{ $t('CHANNEL_CONNECT.INFO.RISK_OWN_ACCOUNT') }}</li>
          <li>{{ $t('CHANNEL_CONNECT.INFO.RISK_2FA') }}</li>
        </ul>
      </section>
      <label class="flex items-start gap-3 text-sm text-n-slate-12">
        <input
          v-model="consent"
          type="checkbox"
          class="mt-0.5"
          data-test="consent-checkbox"
        />
        <span>{{ $t('CHANNEL_CONNECT.INFO.CONSENT') }}</span>
      </label>
      <ErrorNotice
        v-if="error"
        :code="error.code"
        :attempts-left="error.attemptsLeft"
      />
      <div class="flex flex-wrap gap-3">
        <NextButton
          blue
          data-test="consent-continue"
          :is-loading="phase === PHASES.STARTING"
          :disabled="!consent || phase === PHASES.STARTING"
          :label="$t('CHANNEL_CONNECT.ACTIONS.CONTINUE')"
          @click="begin"
        />
        <NextButton
          variant="ghost"
          color="slate"
          :label="$t('CHANNEL_CONNECT.ACTIONS.BACK')"
          @click="mode = null"
        />
      </div>
    </div>

    <!-- 3/4. Entrar e validar acesso -->
    <div
      v-else-if="phase === PHASES.STEP"
      class="flex flex-col gap-5 rounded-2xl border border-solid border-n-weak bg-n-solid-1 p-5"
      data-test="login-step"
    >
      <ErrorNotice
        v-if="error"
        :code="error.code"
        :attempts-left="error.attemptsLeft"
      />
      <FieldsStep
        v-if="isFields && !locked"
        :step="step"
        :busy="busy"
        :locked="locked"
        @submit="onSubmitFields"
        @cancel="close"
      />
      <WaitStep v-else-if="waiting" :step="step" @cancel="close" />
      <QrStep
        v-else-if="isQr"
        :step="step"
        :provider="provider"
        @cancel="close"
      />
      <SyncStep v-else-if="kind === 'syncing'" :connection="connection" />
      <div v-if="locked" class="flex gap-3">
        <NextButton
          variant="ghost"
          color="slate"
          :label="$t('CHANNEL_CONNECT.ACTIONS.CLOSE')"
          @click="close"
        />
      </div>
    </div>

    <!-- 5. Finalizar -->
    <div
      v-else-if="phase === PHASES.FINALIZE"
      class="rounded-2xl border border-solid border-n-weak bg-n-solid-1 p-5"
    >
      <ErrorNotice v-if="error" class="mb-4" :code="error.code" />
      <FinalizeStep
        :default-name="$t(titleKey)"
        :busy="busy"
        @submit="onFinalize"
      />
    </div>

    <div
      v-else-if="phase === PHASES.DONE"
      class="flex flex-col items-start gap-4"
      data-test="done-step"
    >
      <p class="m-0 text-sm text-n-slate-12">
        {{ $t('CHANNEL_CONNECT.DONE') }}
      </p>
      <NextButton
        blue
        :label="$t('CHANNEL_CONNECT.ACTIONS.CLOSE')"
        @click="emit('close')"
      />
    </div>

    <div
      v-else
      class="flex flex-col items-start gap-4"
      data-test="cancelled-step"
    >
      <p class="m-0 text-sm text-n-slate-11">
        {{ $t('CHANNEL_CONNECT.CANCELLED') }}
      </p>
      <NextButton
        variant="faded"
        color="slate"
        :label="$t('CHANNEL_CONNECT.ACTIONS.CLOSE')"
        @click="close"
      />
    </div>
  </div>
</template>
