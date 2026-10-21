<script setup>
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import api from 'dashboard/api/channelConnections';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { errorI18nKey } from './errorCodes';
import ConnectChannelWizard from './ConnectChannelWizard.vue';
import { PROVIDERS } from './constants';

// Painel na caixa de entrada: estado, ultima atividade, ultimo erro e versao
// do conector; reconectar abre o mesmo assistente; desconectar/revogar com
// confirmacao.
const props = defineProps({
  inbox: { type: Object, required: true },
  connection: { type: Object, required: true },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();

const showWizard = ref(false);
const confirming = ref(null); // 'disconnect' | 'revoke'
const busy = ref(false);

const provider = computed(
  () =>
    Object.values(PROVIDERS).find(
      p => p.channelType === props.inbox.channel_type
    )?.key || props.connection.provider
);
const needsReauth = computed(() =>
  ['reauth_required', 'degraded'].includes(props.connection.state)
);
const isActive = computed(
  () => !['disconnected', 'revoked'].includes(props.connection.state)
);
const stateColor = computed(() => {
  const s = props.connection.state;
  if (s === 'connected') return 'bg-n-teal-3 text-n-teal-11';
  if (['degraded', 'reauth_required'].includes(s))
    return 'bg-n-amber-3 text-n-amber-11';
  if (['revoked', 'disconnected'].includes(s))
    return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-alpha-2 text-n-slate-11';
});
const lastActivity = computed(() =>
  props.connection.last_activity_at
    ? new Date(props.connection.last_activity_at).toLocaleString()
    : t('CHANNEL_CONNECT.PANEL.NEVER')
);

const confirmAction = async () => {
  const action = confirming.value;
  busy.value = true;
  try {
    await api[action](props.connection.id);
    useAlert(t(`CHANNEL_CONNECT.PANEL.${action.toUpperCase()}_DONE`));
    emit('changed');
  } catch (e) {
    useAlert(t('CHANNEL_CONNECT.ERRORS.GENERIC'));
  } finally {
    busy.value = false;
    confirming.value = null;
  }
};

const onWizardClose = () => {
  showWizard.value = false;
  emit('changed');
};
</script>

<template>
  <section
    class="mx-6 mb-4 flex flex-col gap-4 rounded-2xl border border-solid border-n-weak bg-n-solid-1 p-5"
    data-test="connection-panel"
  >
    <header class="flex flex-wrap items-center justify-between gap-2">
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ $t('CHANNEL_CONNECT.PANEL.TITLE') }}
      </h3>
      <span
        class="rounded-full px-2.5 py-0.5 text-xs font-medium"
        :class="stateColor"
        data-test="panel-state"
      >
        {{ $t(`CHANNEL_CONNECT.STATES.${connection.state.toUpperCase()}`) }}
      </span>
    </header>
    <dl class="m-0 grid grid-cols-1 gap-3 text-sm sm:grid-cols-3">
      <div>
        <dt class="text-xs text-n-slate-10">
          {{ $t('CHANNEL_CONNECT.PANEL.LAST_ACTIVITY') }}
        </dt>
        <dd class="m-0 text-n-slate-12" data-test="panel-activity">
          {{ lastActivity }}
        </dd>
      </div>
      <div>
        <dt class="text-xs text-n-slate-10">
          {{ $t('CHANNEL_CONNECT.PANEL.LAST_ERROR') }}
        </dt>
        <dd class="m-0 text-n-slate-12" data-test="panel-error">
          {{
            connection.last_error_code
              ? $t(errorI18nKey(connection.last_error_code))
              : $t('CHANNEL_CONNECT.PANEL.NO_ERROR')
          }}
        </dd>
      </div>
      <div>
        <dt class="text-xs text-n-slate-10">
          {{ $t('CHANNEL_CONNECT.PANEL.CONNECTOR_VERSION') }}
        </dt>
        <dd class="m-0 text-n-slate-12" data-test="panel-version">
          {{ connection.connector_version || '-' }}
        </dd>
      </div>
    </dl>

    <div
      v-if="confirming"
      class="rounded-xl border border-solid border-n-ruby-6 bg-n-ruby-3 p-4"
      data-test="confirm-box"
    >
      <p class="m-0 mb-3 text-sm text-n-ruby-11">
        {{ $t(`CHANNEL_CONNECT.PANEL.CONFIRM_${confirming.toUpperCase()}`) }}
      </p>
      <div class="flex gap-3">
        <NextButton
          color="ruby"
          :is-loading="busy"
          :label="$t('CHANNEL_CONNECT.PANEL.CONFIRM_YES')"
          data-test="confirm-yes"
          @click="confirmAction"
        />
        <NextButton
          variant="ghost"
          color="slate"
          :label="$t('CHANNEL_CONNECT.ACTIONS.CANCEL')"
          @click="confirming = null"
        />
      </div>
    </div>
    <div v-else class="flex flex-wrap gap-3">
      <NextButton
        v-if="needsReauth || !isActive"
        blue
        :label="$t('CHANNEL_CONNECT.PANEL.RECONNECT')"
        data-test="panel-reconnect"
        @click="showWizard = true"
      />
      <NextButton
        v-if="isActive"
        variant="faded"
        color="slate"
        :label="$t('CHANNEL_CONNECT.PANEL.DISCONNECT')"
        data-test="panel-disconnect"
        @click="confirming = 'disconnect'"
      />
      <NextButton
        v-if="connection.state !== 'revoked'"
        variant="ghost"
        color="ruby"
        :label="$t('CHANNEL_CONNECT.PANEL.REVOKE')"
        data-test="panel-revoke"
        @click="confirming = 'revoke'"
      />
    </div>

    <div
      v-if="showWizard"
      class="fixed inset-0 z-50 flex items-start justify-center overflow-auto bg-black/50 p-4"
      role="dialog"
      aria-modal="true"
    >
      <div
        class="my-8 w-full max-w-xl rounded-2xl bg-n-solid-1 p-6 shadow-xl sm:p-8"
      >
        <ConnectChannelWizard
          :provider="provider"
          :reauth-connection-id="connection.id"
          @close="onWizardClose"
          @done="onWizardClose"
        />
      </div>
    </div>
  </section>
</template>
