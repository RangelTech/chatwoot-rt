<script setup>
import { useI18n } from 'vue-i18n';
import SocialUnofficialConnect from './SocialUnofficialConnect.vue';

const { t } = useI18n();
</script>

<template>
  <SocialUnofficialConnect
    provider="facebook_web"
    :title="t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.FACEBOOK.TITLE')"
    :description="t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.FACEBOOK.DESC')"
  />
</template>
