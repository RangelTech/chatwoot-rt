<script setup>
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const { axios } = window;
const { t } = useI18n();
const route = useRoute();
const base = '/api/v1/accounts/' + route.params.accountId + '/rt_ai';
const inboxes = ref([]);
const queues = ref([]);
const templates = ref([]);
const loading = ref(true);
const unavailable = ref(false);
const busy = ref('');
const newQueue = ref({ name: '', description: '', respondent_kind: 'ia', template_id: '', mode: 'piloto', destination_team_ids: [] });

const load = async () => {
  loading.value = true;
  try {
    const [queueResponse, templateResponse] = await Promise.all([axios.get(base + '/queues'), axios.get(base + '/chats/templates')]);
    inboxes.value = queueResponse.data.inboxes || [];
    queues.value = queueResponse.data.queues || [];
    templates.value = Array.isArray(templateResponse.data) ? templateResponse.data : templateResponse.data.templates || [];
    unavailable.value = false;
  } catch (_) { unavailable.value = true; } finally { loading.value = false; }
};
const errorMessage = error => error.response?.data?.message || t('RAGENT.RES.ERROR');
const saveEntry = async inbox => {
  busy.value = 'entry-' + inbox.id;
  try {
    const { data } = await axios.put(base + '/queues/entry', { inbox_id: inbox.id, routing_mode: inbox.routing_mode, team_id: inbox.entry_team_id || null });
    Object.assign(inbox, data);
    useAlert(t('RAGENT.INBOXES.SAVED'));
  } catch (error) { useAlert(errorMessage(error)); } finally { busy.value = ''; }
};
// Atalho: agente de atendimento => cria/reaproveita a fila de IA do agente e a torna a fila de entrada da caixa.
const pickServiceAgent = async (inbox, templateId) => {
  if (!templateId) return;
  busy.value = 'entry-' + inbox.id;
  try {
    let queue = queues.value.find(item => item.respondent_kind === 'ia' && item.template_id === templateId);
    if (!queue) {
      const template = templates.value.find(item => item.id === templateId);
      const { data } = await axios.post(base + '/queues', { name: 'IA · ' + (template?.name || ''), description: template?.name || '', respondent_kind: 'ia', template_id: templateId, mode: 'piloto', destination_team_ids: [] });
      queues.value.push(data);
      queue = data;
    }
    inbox.entry_team_id = queue.id;
    if (inbox.routing_mode === 'legado') inbox.routing_mode = 'sombra';
    await saveEntry(inbox);
  } catch (error) { useAlert(errorMessage(error) || t('RAGENT.INBOXES.SHORTCUT_FAILED')); } finally { busy.value = ''; }
};
const createQueue = async () => {
  busy.value = 'new';
  try {
    const { data } = await axios.post(base + '/queues', newQueue.value);
    queues.value.push(data);
    newQueue.value = { name: '', description: '', respondent_kind: 'ia', template_id: '', mode: 'piloto', destination_team_ids: [] };
    useAlert(t('RAGENT.INBOXES.QUEUE_CREATED'));
  } catch (error) { useAlert(errorMessage(error)); } finally { busy.value = ''; }
};
const saveQueue = async queue => {
  busy.value = 'queue-' + queue.id;
  try {
    const { data } = await axios.put(base + '/queues/' + queue.id, queue);
    Object.assign(queue, data);
    useAlert(t('RAGENT.INBOXES.SAVED'));
  } catch (error) { useAlert(errorMessage(error)); } finally { busy.value = ''; }
};
const removeQueue = async queue => {
  if (!window.confirm(t('RAGENT.INBOXES.CONFIRM_DELETE', { name: queue.name }))) return;
  busy.value = 'queue-' + queue.id;
  try {
    await axios.delete(base + '/queues/' + queue.id, { data: { destination_team_id: queue.delete_destination_team_id || null } });
    queues.value = queues.value.filter(item => item.id !== queue.id);
    inboxes.value.forEach(inbox => { if (inbox.entry_team_id === queue.id) inbox.entry_team_id = null; });
  } catch (error) { useAlert(errorMessage(error)); } finally { busy.value = ''; }
};
onMounted(load);
</script>

<template>
  <div class="mx-auto flex h-full w-full max-w-5xl flex-col gap-6 overflow-y-auto p-6">
    <section><h1 class="text-heading-1 text-n-slate-12">{{ t('RAGENT.INBOXES.TITLE') }}</h1><p class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.HELP') }}</p></section>
    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="unavailable" class="text-n-slate-11">{{ t('RAGENT.CHAT.FORBIDDEN') }}</p>
    <template v-else>
      <section class="rounded-xl border border-n-weak p-4">
        <h2 class="mb-3 text-heading-2 text-n-slate-12">{{ t('RAGENT.INBOXES.ENTRY_TITLE') }}</h2>
        <p class="mb-3 text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.ENTRY_HELP') }}</p>
        <ul class="divide-y divide-n-weak">
          <li v-for="inbox in inboxes" :key="inbox.id" class="flex flex-wrap items-center gap-3 py-3">
            <div class="min-w-40 flex-1"><p class="text-body-main text-n-slate-12">{{ inbox.name }}</p><p class="text-sm text-n-slate-11">{{ inbox.channel_type }}</p></div>
            <select v-model="inbox.routing_mode" class="!mb-0 w-36" :title="t('RAGENT.INBOXES.ROUTING_MODE_HELP')" :aria-label="inbox.name + ' ' + t('RAGENT.INBOXES.ROUTING_MODE')"><option value="legado">{{ t('RAGENT.INBOXES.MODE_LEGACY') }}</option><option value="sombra">{{ t('RAGENT.INBOXES.MODE_SHADOW') }}</option><option value="filas">{{ t('RAGENT.INBOXES.MODE_QUEUES') }}</option></select>
            <select v-model="inbox.entry_team_id" class="!mb-0 w-56" :disabled="inbox.routing_mode === 'legado'" :aria-label="inbox.name + ' ' + t('RAGENT.INBOXES.ENTRY_QUEUE')"><option :value="null">{{ t('RAGENT.INBOXES.SELECT_QUEUE') }}</option><option v-for="queue in queues" :key="queue.id" :value="queue.id">{{ queue.name }}</option></select>
            <select class="!mb-0 w-56" :value="''" :title="t('RAGENT.INBOXES.SERVICE_AGENT_HELP')" :aria-label="inbox.name + ' ' + t('RAGENT.INBOXES.SERVICE_AGENT')" @change="pickServiceAgent(inbox, $event.target.value)"><option value="">{{ t('RAGENT.INBOXES.PICK_SERVICE_AGENT') }}</option><option v-for="template in templates" :key="template.id" :value="template.id">{{ template.name }}</option></select>
            <Button size="sm" :label="t('RAGENT.RES.SAVE')" :disabled="busy === 'entry-' + inbox.id" @click="saveEntry(inbox)" />
          </li>
          <li v-if="!inboxes.length" class="py-4 text-n-slate-11">{{ t('RAGENT.RES.EMPTY') }}</li>
        </ul>
      </section>
      <section class="rounded-xl border border-n-weak p-4">
        <h2 class="mb-1 text-heading-2 text-n-slate-12">{{ t('RAGENT.INBOXES.QUEUES_TITLE') }}</h2><p class="mb-4 text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.QUEUES_HELP') }}</p>
        <ul class="space-y-3">
          <li v-for="queue in queues" :key="queue.id" class="rounded-lg border border-n-weak p-3">
            <div class="grid gap-3 md:grid-cols-2">
              <label class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.QUEUE_NAME') }}<input v-model="queue.name" class="!mb-0 mt-1 w-full" /></label>
              <label class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.RESPONDENT') }}<select v-model="queue.respondent_kind" class="!mb-0 mt-1 w-full"><option value="humano">{{ t('RAGENT.INBOXES.HUMAN_QUEUE') }}</option><option value="ia">{{ t('RAGENT.INBOXES.AI_QUEUE') }}</option></select></label>
              <label v-if="queue.respondent_kind === 'ia'" class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.AGENT') }}<select v-model="queue.template_id" class="!mb-0 mt-1 w-full"><option value="">{{ t('RAGENT.INBOXES.SELECT_AGENT') }}</option><option v-for="template in templates" :key="template.id" :value="template.id">{{ template.name }}</option></select></label>
              <label v-if="queue.respondent_kind === 'ia'" class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.AI_MODE') }}<select v-model="queue.mode" class="!mb-0 mt-1 w-full" :title="t('RAGENT.INBOXES.AI_MODE_HELP')"><option value="piloto">{{ t('RAGENT.INBOXES.MODE_PILOT') }}</option><option value="desligado">{{ t('RAGENT.INBOXES.MODE_OFF') }}</option></select><span class="mt-1 block text-sm text-n-slate-10">{{ t('RAGENT.INBOXES.AI_MODE_HELP') }}</span></label>
            </div>
            <label class="mt-3 block text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.DESCRIPTION') }}<input v-model="queue.description" class="!mb-0 mt-1 w-full" /></label>
            <fieldset class="mt-3"><legend class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.DESTINATIONS') }}</legend><div class="mt-1 flex flex-wrap gap-x-4 gap-y-2"><label v-for="destination in queues.filter(item => item.id !== queue.id)" :key="destination.id" class="flex items-center gap-1 text-body-main text-n-slate-11"><input v-model="queue.destination_team_ids" type="checkbox" :value="destination.id" />{{ destination.name }}</label></div></fieldset>
            <div class="mt-3 flex flex-wrap gap-2"><Button size="sm" :label="t('RAGENT.RES.SAVE')" :disabled="busy === 'queue-' + queue.id" @click="saveQueue(queue)" /><select v-model="queue.delete_destination_team_id" class="!mb-0 w-56"><option :value="null">{{ t('RAGENT.INBOXES.DELETE_DESTINATION') }}</option><option v-for="destination in queues.filter(item => item.id !== queue.id)" :key="destination.id" :value="destination.id">{{ destination.name }}</option></select><Button size="sm" color="ruby" :label="t('RAGENT.RES.DELETE')" :disabled="busy === 'queue-' + queue.id" @click="removeQueue(queue)" /></div>
          </li>
          <li v-if="!queues.length" class="text-n-slate-11">{{ t('RAGENT.INBOXES.NO_QUEUES') }}</li>
        </ul>
      </section>
      <section class="rounded-xl border border-n-weak p-4">
        <h2 class="mb-3 text-heading-2 text-n-slate-12">{{ t('RAGENT.INBOXES.NEW_QUEUE') }}</h2>
        <p class="mb-3 text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.QUEUE_EXAMPLE') }}</p>
        <div class="grid gap-3 md:grid-cols-2"><input v-model="newQueue.name" class="!mb-0" :placeholder="t('RAGENT.INBOXES.QUEUE_NAME_EXAMPLE')" /><select v-model="newQueue.respondent_kind" class="!mb-0" :aria-label="t('RAGENT.INBOXES.RESPONDENT')"><option value="ia">{{ t('RAGENT.INBOXES.AI_QUEUE') }}</option><option value="humano">{{ t('RAGENT.INBOXES.HUMAN_QUEUE') }}</option></select><select v-if="newQueue.respondent_kind === 'ia'" v-model="newQueue.template_id" class="!mb-0" :aria-label="t('RAGENT.INBOXES.AGENT')"><option value="">{{ t('RAGENT.INBOXES.SELECT_AGENT') }}</option><option v-for="template in templates" :key="template.id" :value="template.id">{{ template.name }}</option></select><select v-if="newQueue.respondent_kind === 'ia'" v-model="newQueue.mode" class="!mb-0" :title="t('RAGENT.INBOXES.AI_MODE_HELP')" :aria-label="t('RAGENT.INBOXES.AI_MODE')"><option value="piloto">{{ t('RAGENT.INBOXES.MODE_PILOT') }}</option><option value="desligado">{{ t('RAGENT.INBOXES.MODE_OFF') }}</option></select></div>
        <input v-model="newQueue.description" class="!mb-0 mt-3 w-full" :placeholder="t('RAGENT.INBOXES.DESCRIPTION')" />
        <fieldset class="mt-3"><legend class="text-body-main text-n-slate-11">{{ t('RAGENT.INBOXES.DESTINATIONS') }}</legend><div class="mt-1 flex flex-wrap gap-x-4 gap-y-2"><label v-for="destination in queues" :key="destination.id" class="flex items-center gap-1 text-body-main text-n-slate-11"><input v-model="newQueue.destination_team_ids" type="checkbox" :value="destination.id" />{{ destination.name }}</label></div></fieldset>
        <Button class="mt-3" :label="t('RAGENT.INBOXES.CREATE_QUEUE')" :disabled="busy === 'new' || !newQueue.name" @click="createQueue" />
      </section>
    </template>
  </div>
</template>
