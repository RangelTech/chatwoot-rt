<script setup>
// Fase F (F-8d): indicador de quem responde a conversa. Só leitura; em modo legado não renderiza nada.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  accountId: { type: [Number, String], required: true },
  version: { type: String, default: '' },
});

const { axios } = window;
const { t } = useI18n();
const info = ref(null);

const load = async () => {
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${props.accountId}/rt_ai/queues/respondent`,
      { params: { conversation_id: props.conversationId } }
    );
    info.value = data;
  } catch {
    info.value = null;
  }
};
watch(() => [props.conversationId, props.version], load, { immediate: true });

const label = computed(() => {
  const i = info.value;
  if (!i || !i.respondent) return '';
  if (i.respondent === 'ia') return t('RAGENT.INBOXES.BADGE_AI', { queue: i.queue_name });
  if (i.respondent === 'humano' && i.reason === 'modo_desligado') return t('RAGENT.INBOXES.BADGE_AI_OFF', { queue: i.queue_name });
  if (i.respondent === 'humano' && i.assignee_name) return t('RAGENT.INBOXES.BADGE_PERSON', { name: i.assignee_name });
  if (i.respondent === 'humano') return t('RAGENT.INBOXES.BADGE_HUMAN', { queue: i.queue_name || '-' });
  return t('RAGENT.INBOXES.BADGE_NONE');
});
const tone = computed(() => (info.value?.respondent === 'ia' ? 'bg-n-iris-3 text-n-iris-11' : 'bg-n-alpha-2 text-n-slate-11'));
</script>

<template>
  <span v-if="label" class="inline-flex min-w-0 items-center gap-1">
    <span>•</span>
    <span
      data-testid="respondent-badge"
      class="inline-flex max-w-full items-center truncate rounded-md px-2 py-0.5 text-xs font-medium"
      :class="tone"
    >
      {{ label }}
    </span>
  </span>
</template>
