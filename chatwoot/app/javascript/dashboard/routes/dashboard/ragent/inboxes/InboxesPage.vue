<script setup>
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const { axios } = window;
const { t } = useI18n();
const route = useRoute();
const base = `/api/v1/accounts/${route.params.accountId}/rt_ai`;

const inboxes = ref([]);
const templates = ref([]);
const loading = ref(true);
const forbidden = ref(false);
const busy = ref('');

const load = async () => {
  try {
    const [i, tp] = await Promise.all([
      axios.get(`${base}/resources/inboxes`),
      axios.get(`${base}/chats/templates`),
    ]);
    inboxes.value = (i.data.items || i.data.inboxes || i.data || []).map(x => ({
      ...x,
      // O motor identifica a caixa por `chatwoot_inbox_id`; sem `id` o PUT ia para /inboxes/undefined (404).
      id: x.id ?? x.chatwoot_inbox_id,
      template_id: x.template_id || x.ai?.template_id || '',
      autopilot: x.autopilot ?? x.ai?.autopilot ?? true,
      degraded: !!x.ai?.degraded,
    }));
    templates.value = tp.data || [];
  } catch (error) {
    forbidden.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(load);

const save = async inbox => {
  busy.value = String(inbox.id);
  try {
    const { data } = await axios.put(`${base}/resources/inboxes/${inbox.id}`, {
      template_id: inbox.template_id || null,
      autopilot: inbox.autopilot,
    });
    // Vínculo salvo, mas o aviso ao atendimento automático falhou: nunca mostrar sucesso silencioso.
    inbox.degraded = data?.status === 'degraded';
    useAlert(t(inbox.degraded ? 'RAGENT.INBOXES.DEGRADED' : 'RAGENT.RES.SAVED'));
  } catch (error) {
    useAlert(t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = '';
  }
};
</script>

<template>
  <div class="mx-auto flex h-full w-full max-w-5xl flex-col gap-4 overflow-y-auto p-6">
    <h1 class="text-heading-1 text-n-slate-12">{{ t('RAGENT.INBOXES.TITLE') }}</h1>
    <p class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.HELP') }}</p>
    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="forbidden" class="text-n-slate-11">{{ t('RAGENT.CHAT.FORBIDDEN') }}</p>
    <ul v-else class="divide-y divide-n-weak rounded-xl border border-n-weak">
      <li v-for="i in inboxes" :key="i.id" class="flex flex-wrap items-center gap-3 px-4 py-3">
        <div class="min-w-0 flex-1">
          <p class="truncate text-body-main text-n-slate-12">{{ i.name }}</p>
          <p class="truncate text-body-main text-n-slate-11">{{ i.channel_type }}</p>
          <p v-if="i.degraded" class="text-body-main text-n-ruby-11">
            {{ t('RAGENT.INBOXES.DEGRADED') }}
          </p>
        </div>
        <select v-model="i.template_id" class="!mb-0 w-64">
          <option value="">{{ t('RAGENT.INBOXES.HUMAN_ONLY') }}</option>
          <option v-for="tp in templates" :key="tp.id" :value="tp.id">{{ tp.name }}</option>
        </select>
        <label class="flex items-center gap-2 text-body-main text-n-slate-11">
          <input v-model="i.autopilot" type="checkbox" class="!mb-0" />
          {{ t('RAGENT.INBOXES.AUTOPILOT') }}
        </label>
        <Button size="sm" :label="t('RAGENT.RES.SAVE')" :disabled="busy === String(i.id)" @click="save(i)" />
      </li>
      <li v-if="!inboxes.length" class="px-4 py-6 text-n-slate-11">{{ t('RAGENT.RES.EMPTY') }}</li>
    </ul>
  </div>
</template>
