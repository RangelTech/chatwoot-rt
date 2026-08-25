<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';

import { useAccount } from 'dashboard/composables/useAccount';

import ChannelItem from 'dashboard/components/widgets/ChannelItem.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId, currentAccount, updateAccount } = useAccount();

const globalConfig = useMapGetter('globalConfig/get');

const enabledFeatures = computed(() => currentAccount.value?.features || {});

// Conectores "não oficiais" (Whatsapp/Instagram/Facebook Unoficial) usam
// sessão de navegador, não API oficial -- alguns tenants preferem nem ver
// essa opção na tela. Config por tenant (account.settings), não global --
// pedido do dono: quem decide é cada empresa, não uma flag de instalação.
const UNOFFICIAL_CHANNEL_KEYS = [
  'evolution_api',
  'instagram_unofficial',
  'facebook_unofficial',
];

const showUnofficialChannels = ref(true);
watch(
  currentAccount,
  () => {
    const stored = currentAccount.value?.settings?.show_unofficial_channels;
    showUnofficialChannels.value = stored ?? true;
  },
  { deep: true, immediate: true }
);

const toggleUnofficialChannels = async () => {
  await updateAccount(
    { show_unofficial_channels: showUnofficialChannels.value },
    { silent: true }
  );
};

const hasTiktokConfigured = computed(() => {
  return window.chatwootConfig?.tiktokAppId;
});

const channelList = computed(() => {
  const { apiChannelName } = globalConfig.value;
  const channels = [
    {
      key: 'website',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WEBSITE.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WEBSITE.DESCRIPTION'),
      icon: 'i-woot-website',
    },
    {
      key: 'facebook',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.FACEBOOK.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.FACEBOOK.DESCRIPTION'),
      icon: 'i-woot-messenger',
    },
    {
      key: 'whatsapp',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP.DESCRIPTION'),
      icon: 'i-woot-whatsapp',
    },
    {
      key: 'wapi',
      title: t('INBOX_MGMT.ADD.WAPI.TITLE'),
      description: t('INBOX_MGMT.ADD.WAPI.DESC'),
      icon: 'i-woot-whatsapp',
    },
    {
      key: 'evolution_api',
      title: t('INBOX_MGMT.ADD.EVOLUTION_API.TITLE'),
      description: t('INBOX_MGMT.ADD.EVOLUTION_API.DESC'),
      icon: 'i-woot-whatsapp',
    },
    {
      key: 'instagram_unofficial',
      title: t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.INSTAGRAM.TITLE'),
      description: t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.INSTAGRAM.DESC'),
      icon: 'i-woot-instagram',
    },
    {
      key: 'facebook_unofficial',
      title: t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.FACEBOOK.TITLE'),
      description: t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.FACEBOOK.DESC'),
      icon: 'i-woot-messenger',
    },
    {
      key: 'sms',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.SMS.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.SMS.DESCRIPTION'),
      icon: 'i-woot-sms',
    },
    {
      key: 'email',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.EMAIL.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.EMAIL.DESCRIPTION'),
      icon: 'i-woot-mail',
    },
    {
      key: 'api',
      title: apiChannelName || t('INBOX_MGMT.ADD.AUTH.CHANNEL.API.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.API.DESCRIPTION'),
      icon: 'i-woot-api',
    },
    {
      key: 'telegram',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TELEGRAM.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TELEGRAM.DESCRIPTION'),
      icon: 'i-woot-telegram',
    },
    {
      key: 'line',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.LINE.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.LINE.DESCRIPTION'),
      icon: 'i-woot-line',
    },
    {
      key: 'instagram',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.INSTAGRAM.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.INSTAGRAM.DESCRIPTION'),
      icon: 'i-woot-instagram',
    },
  ];

  if (hasTiktokConfigured.value) {
    channels.push({
      key: 'tiktok',
      title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TIKTOK.TITLE'),
      description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.TIKTOK.DESCRIPTION'),
      icon: 'i-woot-tiktok',
    });
  }

  channels.push({
    key: 'voice',
    title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.VOICE.TITLE'),
    description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.VOICE.DESCRIPTION'),
    icon: 'i-woot-voice',
  });

  channels.push({
    key: 'whatsapp_call',
    title: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP_CALL.TITLE'),
    description: t('INBOX_MGMT.ADD.AUTH.CHANNEL.WHATSAPP_CALL.DESCRIPTION'),
    icon: 'i-woot-whatsapp',
  });

  return channels;
});

const visibleChannelList = computed(() => {
  if (showUnofficialChannels.value) return channelList.value;
  return channelList.value.filter(
    channel => !UNOFFICIAL_CHANNEL_KEYS.includes(channel.key)
  );
});

const initChannelAuth = channel => {
  const params = {
    sub_page: channel,
    accountId: accountId.value,
  };
  router.push({ name: 'settings_inboxes_page_channel', params });
};
</script>

<template>
  <div class="max-w-3xl">
    <div
      class="flex items-center justify-between gap-4 px-8 pt-6 -mb-2 text-sm text-n-slate-11"
    >
      <span>{{ t('INBOX_MGMT.ADD.UNOFFICIAL_TOGGLE.LABEL') }}</span>
      <Switch
        v-model="showUnofficialChannels"
        @change="toggleUnofficialChannels"
      />
    </div>
    <div
      class="grid max-w-3xl grid-cols-1 xs:grid-cols-2 mx-0 gap-6 sm:grid-cols-3 p-8"
    >
      <ChannelItem
        v-for="channel in visibleChannelList"
        :key="channel.key"
        :channel="channel"
        :enabled-features="enabledFeatures"
        @channel-item-click="initChannelAuth"
      />
    </div>
  </div>
</template>
