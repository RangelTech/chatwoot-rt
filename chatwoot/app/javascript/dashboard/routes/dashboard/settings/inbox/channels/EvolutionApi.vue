<script setup>
import { ref } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import InboxesAPI from 'dashboard/api/inboxes';

const instanceName = ref('');
const apiUrl = ref('');
const apiKey = ref('');
const qrCode = ref('');
const inboxId = ref(null);
const store = useStore();
const { t } = useI18n();
const router = useRouter();
const v$ = useVuelidate(
  { instanceName: { required }, apiUrl: { required, url }, apiKey: { required } },
  { instanceName, apiUrl, apiKey }
);

const createChannel = async () => {
  const valid = await v$.value.$validate();
  if (!valid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      channel: {
        type: 'evolution_api',
        instance_name: instanceName.value,
        api_url: apiUrl.value,
        api_key: apiKey.value,
      },
    });
    inboxId.value = inbox.id;
    const response = await InboxesAPI.connectEvolution(inbox.id);
    qrCode.value = response.data.qr_code;
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.EVOLUTION_API.ERROR_MESSAGE'));
  }
};

const continueSetup = () => {
  router.replace({ name: 'settings_inboxes_add_agents', params: { page: 'new', inbox_id: inboxId.value } });
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader :header-title="t('INBOX_MGMT.ADD.EVOLUTION_API.TITLE')" :header-content="t('INBOX_MGMT.ADD.EVOLUTION_API.DESC')" />
    <form v-if="!inboxId" class="flex flex-col gap-4 max-w-xl" @submit.prevent="createChannel">
      <label>{{ t('INBOX_MGMT.ADD.EVOLUTION_API.INSTANCE_NAME') }}<input v-model="instanceName" type="text" :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_API.INSTANCE_NAME_PLACEHOLDER')" @blur="v$.instanceName.$touch" /></label>
      <label>{{ t('INBOX_MGMT.ADD.EVOLUTION_API.API_URL') }}<input v-model="apiUrl" type="url" :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_API.API_URL_PLACEHOLDER')" @blur="v$.apiUrl.$touch" /></label>
      <label>{{ t('INBOX_MGMT.ADD.EVOLUTION_API.API_KEY') }}<input v-model="apiKey" type="password" :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_API.API_KEY_PLACEHOLDER')" @blur="v$.apiKey.$touch" /></label>
      <NextButton type="submit" solid blue :label="t('INBOX_MGMT.ADD.EVOLUTION_API.SUBMIT_BUTTON')" />
    </form>
    <div v-else class="flex flex-col gap-4 max-w-xl">
      <img v-if="qrCode" :src="qrCode" :alt="t('INBOX_MGMT.ADD.EVOLUTION_API.QR_ALT')" class="w-64 h-64" />
      <p>{{ t('INBOX_MGMT.ADD.EVOLUTION_API.QR_HELP') }}</p>
      <NextButton type="button" solid blue :label="t('INBOX_MGMT.ADD.EVOLUTION_API.CONTINUE_BUTTON')" @click="continueSetup" />
    </div>
  </div>
</template>
