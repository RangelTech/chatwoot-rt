<script setup>
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

defineProps({
  step: { type: Object, required: true },
});
const emit = defineEmits(['cancel']);
</script>

<template>
  <div
    class="flex flex-col items-center gap-4 py-6 text-center"
    data-test="wait-step"
  >
    <Spinner :size="28" />
    <h3 class="m-0 text-base font-medium text-n-slate-12">
      {{ $t('CHANNEL_CONNECT.STEPS.APPROVAL_TITLE') }}
    </h3>
    <p class="m-0 max-w-sm text-sm text-n-slate-11">
      {{ $t('CHANNEL_CONNECT.STEPS.APPROVAL_HELP') }}
    </p>
    <NextButton
      v-if="step.wait?.can_cancel !== false"
      variant="ghost"
      color="slate"
      :label="$t('CHANNEL_CONNECT.ACTIONS.CANCEL')"
      @click="emit('cancel')"
    />
  </div>
</template>
