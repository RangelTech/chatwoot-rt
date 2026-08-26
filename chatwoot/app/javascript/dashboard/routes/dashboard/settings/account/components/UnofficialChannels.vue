<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

// produto-05 (mega-spec-reestrutura) -- movido de ChannelList.vue (tela de
// Adicionar canal) pra cá. Dois motivos do dono: (1) homologação Meta --
// o botão não pode aparecer gravando a tela do Chatwoot pro App Review;
// (2) controle de acesso -- Configurações -> Conta já é só pra
// administrador, mesmo padrão de AudioTranscription.vue/AccountId.vue,
// sem precisar de gate de permissão novo. Default muda de true pra false
// (decidido 25/08/2026).
const { t } = useI18n();
const isEnabled = ref(false);

const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    const stored = currentAccount.value?.settings?.show_unofficial_channels;
    isEnabled.value = stored ?? false;
  },
  { deep: true, immediate: true }
);

const toggleUnofficialChannels = async () => {
  await updateAccount(
    { show_unofficial_channels: isEnabled.value },
    { silent: true }
  );
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.UNOFFICIAL_CHANNELS.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.UNOFFICIAL_CHANNELS.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggleUnofficialChannels" />
      </div>
    </template>
  </SectionLayout>
</template>
