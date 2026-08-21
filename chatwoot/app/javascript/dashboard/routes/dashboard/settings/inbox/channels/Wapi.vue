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

const projectId = ref('');
const token = ref('');
const store = useStore();
const { t } = useI18n();
const router = useRouter();
const v$ = useVuelidate({ projectId: { required }, token: { required } }, { projectId, token });

const createChannel = async () => {
  const valid = await v$.value.$validate();
  if (!valid) return;

  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      channel: { type: 'wapi', project_id: projectId.value, token: token.value },
    });
    router.replace({ name: 'settings_inboxes_add_agents', params: { page: 'new', inbox_id: inbox.id } });
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.WAPI.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader :header-title="t('INBOX_MGMT.ADD.WAPI.TITLE')" :header-content="t('INBOX_MGMT.ADD.WAPI.DESC')" />
    <form class="flex flex-col gap-4 max-w-xl" @submit.prevent="createChannel">
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
  </div>
</template>
