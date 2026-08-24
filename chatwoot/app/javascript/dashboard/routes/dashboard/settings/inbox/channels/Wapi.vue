<script setup>
import { ref } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const inboxName = ref('');
const projectId = ref('');
const token = ref('');
const callbackUrl = ref('');
const inboxId = ref(null);
const store = useStore();
const { t } = useI18n();
const router = useRouter();
const v$ = useVuelidate(
  { inboxName: { required }, projectId: { required }, token: { required } },
  { inboxName, projectId, token }
);

const createChannel = async () => {
  const valid = await v$.value.$validate();
  if (!valid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value.trim(),
      channel: { type: 'wapi', project_id: projectId.value, token: token.value },
    });
    // The verification token is generated server-side. Show the exact callback
    // only after the inbox exists, otherwise users would paste a URL that cannot
    // authenticate WAPI deliveries.
    inboxId.value = inbox.id;
    callbackUrl.value = inbox.callback_webhook_url;
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.WAPI.ERROR_MESSAGE'));
  }
};

const continueSetup = () => {
  router.replace({ name: 'settings_inboxes_add_agents', params: { page: 'new', inbox_id: inboxId.value } });
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader :header-title="t('INBOX_MGMT.ADD.WAPI.TITLE')" :header-content="t('INBOX_MGMT.ADD.WAPI.DESC')" />
    <form v-if="!inboxId" class="flex flex-col gap-4 max-w-xl" @submit.prevent="createChannel">
      <label>
        {{ t('INBOX_MGMT.ADD.WAPI.INBOX_NAME') }}
        <input v-model="inboxName" type="text" :placeholder="t('INBOX_MGMT.ADD.WAPI.INBOX_NAME_PLACEHOLDER')" @blur="v$.inboxName.$touch" />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.WAPI.APP_ID') }}
        <input v-model="projectId" type="text" :placeholder="t('INBOX_MGMT.ADD.WAPI.APP_ID_PLACEHOLDER')" @blur="v$.projectId.$touch" />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.WAPI.TOKEN') }}
        <input v-model="token" type="password" :placeholder="t('INBOX_MGMT.ADD.WAPI.TOKEN_PLACEHOLDER')" @blur="v$.token.$touch" />
      </label>
      <NextButton type="submit" solid blue :label="t('INBOX_MGMT.ADD.WAPI.SUBMIT_BUTTON')" />
    </form>
    <div v-else class="flex flex-col gap-4 max-w-xl">
      <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-4">
        <h3 class="mb-2 text-base font-medium text-n-slate-12">Configure o callback no WAPI</h3>
        <p class="mb-3 text-sm leading-relaxed text-n-slate-11">
          No painel da sua instância WAPI, cadastre esta URL como webhook de mensagens recebidas. Use método POST e mantenha o parâmetro <code>verify_token</code> exatamente como está.
        </p>
        <label class="text-sm font-medium text-n-slate-12">
          URL de callback
          <input :value="callbackUrl" readonly class="mt-1 w-full" @focus="$event.target.select()" />
        </label>
      </div>
      <NextButton type="button" solid blue label="Continuar para adicionar agentes" @click="continueSetup" />
    </div>
  </div>
</template>
