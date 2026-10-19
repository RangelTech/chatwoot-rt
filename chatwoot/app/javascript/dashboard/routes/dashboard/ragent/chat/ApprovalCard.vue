<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import rtAiChat from 'dashboard/api/rtAiChat';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  approval: { type: Object, required: true },
  canDecide: { type: Boolean, default: false },
});
const emit = defineEmits(['decided']);

const { t } = useI18n();

// pending | approved | denied | expired | already
const status = ref(props.approval.status || 'pending');
const busy = ref(false);
const failed = ref(false);
const now = ref(Date.now());
let timer = null;

const expiresAt = computed(() => new Date(props.approval.expires_at).getTime());
const remaining = computed(() =>
  Math.max(0, Math.round((expiresAt.value - now.value) / 1000))
);
const isPending = computed(
  () => status.value === 'pending' && remaining.value > 0
);
const countdown = computed(() => {
  const m = Math.floor(remaining.value / 60);
  const s = String(remaining.value % 60).padStart(2, '0');
  return `${m}:${s}`;
});
const risk = computed(() =>
  ['low', 'medium', 'high'].includes(props.approval.risk)
    ? props.approval.risk
    : 'medium'
);
const riskClass = computed(
  () =>
    ({
      low: 'bg-n-teal-3 text-n-teal-11',
      medium: 'bg-n-amber-3 text-n-amber-11',
      high: 'bg-n-ruby-3 text-n-ruby-11',
    })[risk.value]
);
const stateText = computed(() => {
  if (status.value === 'approved') return t('RAGENT.CHAT.APPROVAL.APPROVED');
  if (status.value === 'denied') return t('RAGENT.CHAT.APPROVAL.DENIED');
  if (status.value === 'already') return t('RAGENT.CHAT.APPROVAL.ALREADY');
  return t('RAGENT.CHAT.APPROVAL.EXPIRED');
});

const decide = async decision => {
  if (busy.value || !isPending.value) return;
  busy.value = true;
  failed.value = false;
  try {
    const { data } = await rtAiChat.decideApproval(
      props.approval.approval_id,
      decision
    );
    status.value =
      data.status || (decision === 'approve' ? 'approved' : 'denied');
    emit('decided', { id: props.approval.approval_id, status: status.value });
  } catch (error) {
    if (error?.response?.status === 409) status.value = 'already';
    else failed.value = true;
  } finally {
    busy.value = false;
  }
};

onMounted(() => {
  timer = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});
onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <div
    class="max-w-[80%] rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
    role="group"
    :aria-label="t('RAGENT.CHAT.APPROVAL.TITLE')"
    data-testid="approval-card"
  >
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-heading-3 text-n-slate-12">
        {{ t('RAGENT.CHAT.APPROVAL.TITLE') }}
      </span>
      <span class="rounded-md px-2 py-0.5 text-body-main" :class="riskClass">
        {{ t(`RAGENT.CHAT.APPROVAL.RISK.${risk}`) }}
      </span>
      <span v-if="isPending" class="ms-auto text-body-main text-n-slate-11">
        {{ t('RAGENT.CHAT.APPROVAL.EXPIRES_IN', { time: countdown }) }}
      </span>
    </div>
    <p class="mt-2 whitespace-pre-wrap text-body-main text-n-slate-12">
      {{ approval.summary }}
    </p>
    <div v-if="isPending" class="mt-3 flex gap-2">
      <template v-if="canDecide">
        <Button
          :label="t('RAGENT.CHAT.APPROVAL.APPROVE')"
          size="sm"
          :is-loading="busy"
          :disabled="busy"
          @click="decide('approve')"
        />
        <Button
          :label="t('RAGENT.CHAT.APPROVAL.DENY')"
          size="sm"
          color="ruby"
          variant="faded"
          :disabled="busy"
          @click="decide('deny')"
        />
      </template>
      <p v-else class="text-body-main text-n-slate-11">
        {{ t('RAGENT.CHAT.APPROVAL.NO_PERMISSION') }}
      </p>
    </div>
    <p v-else class="mt-3 text-body-main text-n-slate-11">{{ stateText }}</p>
    <p v-if="failed" class="mt-2 text-body-main text-n-ruby-11" role="alert">
      {{ t('RAGENT.CHAT.APPROVAL.ERROR') }}
    </p>
  </div>
</template>
