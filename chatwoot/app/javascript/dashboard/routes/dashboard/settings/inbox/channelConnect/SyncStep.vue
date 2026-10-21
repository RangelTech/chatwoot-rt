<script setup>
import { computed } from 'vue';

const props = defineProps({
  connection: { type: Object, default: null },
});

const progress = computed(() => {
  const raw = props.connection?.sync?.progress;
  if (raw === undefined || raw === null) return null;
  const p = Number(raw);
  if (Number.isNaN(p)) return null;
  return Math.max(0, Math.min(100, Math.round(p)));
});
</script>

<template>
  <div class="flex flex-col gap-4" data-test="sync-step">
    <h3 class="m-0 text-base font-medium text-n-slate-12">
      {{ $t('CHANNEL_CONNECT.STEPS.SYNC_TITLE') }}
    </h3>
    <p class="m-0 text-sm text-n-slate-11">
      {{ $t('CHANNEL_CONNECT.STEPS.SYNC_HELP') }}
    </p>
    <div
      class="h-2 w-full overflow-hidden rounded-full bg-n-alpha-2"
      role="progressbar"
      :aria-valuenow="progress ?? undefined"
      aria-valuemin="0"
      aria-valuemax="100"
    >
      <div
        class="h-full rounded-full bg-n-blue-9 transition-all duration-500"
        :class="{ 'animate-pulse': progress === null }"
        :style="{ width: `${progress ?? 40}%` }"
        data-test="sync-bar"
      />
    </div>
    <p v-if="progress !== null" class="m-0 text-xs text-n-slate-10">
      {{ progress }}%
    </p>
  </div>
</template>
