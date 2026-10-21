<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { errorI18nKey } from './errorCodes';

const props = defineProps({
  code: { type: String, required: true },
  attemptsLeft: { type: Number, default: null },
});

const messageKey = computed(() =>
  props.code === 'consent_required'
    ? 'CHANNEL_CONNECT.ERRORS.CONSENT_REQUIRED'
    : errorI18nKey(props.code)
);
</script>

<template>
  <div
    role="alert"
    class="flex items-start gap-3 rounded-xl border border-solid border-n-ruby-6 bg-n-ruby-3 px-4 py-3 text-sm text-n-ruby-11"
  >
    <Icon icon="i-lucide-circle-alert" class="mt-0.5 size-4 shrink-0" />
    <div class="flex flex-col gap-1">
      <p class="m-0">{{ $t(messageKey) }}</p>
      <p v-if="attemptsLeft !== null" class="m-0 text-xs opacity-80">
        {{ $t('CHANNEL_CONNECT.ERRORS.ATTEMPTS_LEFT', { count: attemptsLeft }) }}
      </p>
    </div>
  </div>
</template>
