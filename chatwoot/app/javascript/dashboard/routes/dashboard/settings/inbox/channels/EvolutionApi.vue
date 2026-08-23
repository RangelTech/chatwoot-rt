<script setup>
import { ref, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import NextButton from 'dashboard/components-next/button/Button.vue';
import InboxesAPI from 'dashboard/api/inboxes';
import PageHeader from '../../SettingsSubPageHeader.vue';

// Produto-05 seção 4 -- QR automático. O administrador do tenant nunca
// escolhe/digita instance_name, URL da Evolution ou API key: a única ação
// dele aqui é clicar em "Criar conexão"; tudo o resto (provisionar a
// instância isolada na VPS, gerar o QR, confirmar a conexão) é derivado do
// backend a partir da sessão autenticada.
const STEP = { START: 'start', PROVISIONING: 'provisioning', QR: 'qr', CONNECTED: 'connected' };

const step = ref(STEP.START);
const qrCode = ref('');
const inboxId = ref(null);
const errorMessage = ref('');
const { t } = useI18n();
const router = useRouter();

let pollTimer = null;

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const pollConnectionStatus = () => {
  stopPolling();
  pollTimer = setInterval(async () => {
    try {
      const response = await InboxesAPI.connectEvolution(inboxId.value);
      const state = response.data?.connection_status?.state;
      if (response.data?.qr_code) qrCode.value = response.data.qr_code;
      if (state === 'open') {
        step.value = STEP.CONNECTED;
        stopPolling();
      }
    } catch (error) {
      // Falha pontual de rede/health check durante o polling não é fatal --
      // a próxima tentativa pode passar; só a criação inicial é fim de jogo.
    }
  }, 5000);
};

const startProvisioning = async () => {
  step.value = STEP.PROVISIONING;
  errorMessage.value = '';
  try {
    const inbox = await InboxesAPI.provisionEvolution();
    inboxId.value = inbox.data.id;

    const connectResponse = await InboxesAPI.connectEvolution(inboxId.value);
    qrCode.value = connectResponse.data.qr_code || '';
    step.value = STEP.QR;
    pollConnectionStatus();
  } catch (error) {
    step.value = STEP.START;
    errorMessage.value =
      error.response?.data?.error ||
      error.message ||
      t('INBOX_MGMT.ADD.EVOLUTION_API.ERROR_MESSAGE');
    useAlert(errorMessage.value);
  }
};

const continueSetup = () => {
  stopPolling();
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: inboxId.value },
  });
};

onBeforeUnmount(stopPolling);
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.EVOLUTION_API.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.EVOLUTION_API.DESC')"
    />

    <div v-if="step === STEP.START" class="flex flex-col gap-4 max-w-xl">
      <p v-if="errorMessage" class="text-n-ruby-9">{{ errorMessage }}</p>
      <NextButton
        solid
        blue
        :label="t('INBOX_MGMT.ADD.EVOLUTION_API.SUBMIT_BUTTON')"
        @click="startProvisioning"
      />
    </div>

    <div v-else-if="step === STEP.PROVISIONING" class="flex flex-col gap-4 max-w-xl">
      <p>{{ t('INBOX_MGMT.ADD.EVOLUTION_API.PROVISIONING') }}</p>
    </div>

    <div v-else-if="step === STEP.QR" class="flex flex-col gap-4 max-w-xl">
      <img
        v-if="qrCode"
        :src="qrCode"
        :alt="t('INBOX_MGMT.ADD.EVOLUTION_API.QR_ALT')"
        class="w-64 h-64"
      />
      <p>{{ t('INBOX_MGMT.ADD.EVOLUTION_API.QR_HELP') }}</p>
    </div>

    <div v-else class="flex flex-col gap-4 max-w-xl">
      <p>{{ t('INBOX_MGMT.ADD.EVOLUTION_API.CONNECTED') }}</p>
      <NextButton
        type="button"
        solid
        blue
        :label="t('INBOX_MGMT.ADD.EVOLUTION_API.CONTINUE_BUTTON')"
        @click="continueSetup"
      />
    </div>
  </div>
</template>
