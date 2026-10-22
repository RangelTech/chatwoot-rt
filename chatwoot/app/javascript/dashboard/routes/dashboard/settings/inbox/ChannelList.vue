<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';

import { useAccount } from 'dashboard/composables/useAccount';

import ChannelItem from 'dashboard/components/widgets/ChannelItem.vue';

const { t } = useI18n();
const router = useRouter();
const { accountId, currentAccount } = useAccount();

const globalConfig = useMapGetter('globalConfig/get');

const enabledFeatures = computed(() => currentAccount.value?.features || {});

// Conectores "não oficiais" (Whatsapp/Instagram/Facebook Unoficial) usam
// sessão de navegador, não API oficial -- alguns tenants preferem nem ver
// essa opção na tela. Config por tenant (account.settings), não global --
// pedido do dono: quem decide é cada empresa, não uma flag de instalação.
// O toggle em si mora em Configurações -> Conta agora (UnofficialChannels.vue,
// produto-05) -- aqui só lê o valor pra filtrar a lista. Motivos da mudança:
// (1) homologação Meta, o botão não pode aparecer gravando a tela do
// Chatwoot pro App Review; (2) controle de acesso, Configurações -> Conta já
// é área só de administrador. Default mudou de true pra false.

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
      title: t('CHANNEL_CONNECT.CATALOG.INSTAGRAM_TITLE'),
      description: t('CHANNEL_CONNECT.CATALOG.INSTAGRAM_DESC'),
      icon: 'i-woot-instagram',
    },
    {
      key: 'facebook_unofficial',
      title: t('CHANNEL_CONNECT.CATALOG.MESSENGER_TITLE'),
      description: t('CHANNEL_CONNECT.CATALOG.MESSENGER_DESC'),
      icon: 'i-woot-messenger',
    },
    {
      key: 'tiktok_unofficial',
      title: t('CHANNEL_CONNECT.CATALOG.TIKTOK_TITLE'),
      description: t('CHANNEL_CONNECT.CATALOG.TIKTOK_DESC'),
      icon: 'i-woot-tiktok',
    },
    {
      key: 'whatsapp_unofficial',
      title: t('CHANNEL_CONNECT.CATALOG.WHATSAPP_TITLE'),
      description: t('CHANNEL_CONNECT.CATALOG.WHATSAPP_DESC'),
      icon: 'i-woot-whatsapp',
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

// Spec 11 §12: duas abas; só o que existe no produto aparece (sem SMS, Line, Telegram, API, voz, Evolution).
const OFFICIAL_KEYS = ['whatsapp', 'instagram', 'facebook', 'email', 'website', 'tiktok'];
const UNOFFICIAL_ORDER = [
  'whatsapp_unofficial',
  'wapi',
  'facebook_unofficial',
  'instagram_unofficial',
  'tiktok_unofficial',
];
const tab = ref('official');
const visibleChannelList = computed(() => {
  if (tab.value === 'official') {
    return channelList.value.filter(c => OFFICIAL_KEYS.includes(c.key));
  }
  return UNOFFICIAL_ORDER.map(k =>
    channelList.value.find(c => c.key === k)
  ).filter(Boolean);
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
    <div class="flex gap-2 px-8 pt-6" role="tablist">
      <button
        v-for="item in ['official', 'unofficial']"
        :key="item"
        type="button"
        role="tab"
        :aria-selected="tab === item"
        class="px-4 py-1.5 text-sm rounded-full border"
        :class="
          tab === item
            ? 'bg-n-brand text-white border-n-brand'
            : 'border-n-weak text-n-slate-11'
        "
        @click="tab = item"
      >
        {{
          item === 'official'
            ? t('INBOX_MGMT.ADD.TABS.OFFICIAL')
            : t('INBOX_MGMT.ADD.TABS.UNOFFICIAL')
        }}
      </button>
    </div>
    <p
      v-if="tab === 'unofficial'"
      class="px-8 pt-3 text-sm text-n-slate-11"
    >
      {{ t('INBOX_MGMT.ADD.TABS.UNOFFICIAL_WARNING') }}
    </p>
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
