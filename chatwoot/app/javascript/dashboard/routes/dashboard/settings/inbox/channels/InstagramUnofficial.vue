<script setup>
import { useI18n } from 'vue-i18n';
import SocialUnofficialConnect from './SocialUnofficialConnect.vue';

const { t } = useI18n();
</script>

<template>
  <SocialUnofficialConnect
    provider="instagram_web"
    :title="t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.INSTAGRAM.TITLE')"
    :description="t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.INSTAGRAM.DESC')"
  />
</template>
