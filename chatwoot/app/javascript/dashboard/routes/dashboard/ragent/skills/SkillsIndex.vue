<script setup>
import { computed, onMounted, ref } from 'vue';
import axios from 'axios';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const base = `/api/v1/accounts/${window.location.pathname.match(/accounts\/(\d+)/)?.[1]}/rt_ai`;

const tab = ref('skills');
const skills = ref([]);
const routines = ref([]);
const proposals = ref([]);
const loading = ref(true);
const forbidden = ref(false);

const list = data => data.items || data.schedules || data.skills || data || [];

const load = async () => {
  loading.value = true;
  forbidden.value = false;
  try {
    const [s, r] = await Promise.all([
      axios.get(`${base}/skills`),
      axios.get(`${base}/skills/routines`),
    ]);
    skills.value = list(s.data);
    routines.value = list(r.data);
  } catch (error) {
    forbidden.value = true;
  }
  try {
    proposals.value = list((await axios.get(`${base}/skills/memory_proposals`)).data);
  } catch (error) {
    proposals.value = [];
  }
  loading.value = false;
};
onMounted(load);

const run = async (verb, url) => {
  try {
    await axios[verb](url);
    await load();
  } catch (error) {
    useAlert(t('RAGENT.SKILLS.ERROR'));
  }
};

const skillAct = (s, action) => run('post', `${base}/skills/${s.id}/act/${action}`);
const routineAct = (r, action) => run('post', `${base}/routines/${r.id}/${action}`);
const routineDelete = r => run('delete', `${base}/routines/${r.id}`);
const memoryAct = (p, action) => run('post', `${base}/memory_proposals/${p.id}/${action}`);

const statusLabel = s => t(`RAGENT.SKILLS.STATUS.${String(s).toUpperCase()}`);
const tabs = computed(() => [
  { key: 'skills', label: t('RAGENT.SKILLS.LEARNED'), count: skills.value.length },
  { key: 'routines', label: t('RAGENT.SKILLS.ROUTINES'), count: routines.value.length },
  { key: 'memories', label: t('RAGENT.SKILLS.MEMORIES'), count: proposals.value.length },
]);
</script>

<template>
  <div class="mx-auto flex h-full w-full max-w-5xl flex-col gap-4 overflow-y-auto p-6">
    <h1 class="text-heading-1 text-n-slate-12">{{ t('RAGENT.SKILLS.TITLE') }}</h1>
    <nav class="flex gap-2 border-b border-n-weak">
      <button
        v-for="x in tabs"
        :key="x.key"
        type="button"
        class="px-3 py-2 text-body-main"
        :class="tab === x.key ? 'border-b-2 border-n-brand text-n-slate-12' : 'text-n-slate-11'"
        @click="tab = x.key"
      >
        {{ x.label }} ({{ x.count }})
      </button>
    </nav>

    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="forbidden" class="text-n-slate-11">{{ t('RAGENT.CHAT.FORBIDDEN') }}</p>

    <ul v-if="tab === 'skills'" class="divide-y divide-n-weak rounded-xl border border-n-weak">
      <li v-for="s in skills" :key="s.id" class="flex items-center gap-3 px-4 py-3">
        <div class="min-w-0 flex-1">
          <p class="truncate text-body-main text-n-slate-12">{{ s.name }}</p>
          <p class="truncate text-body-main text-n-slate-11">{{ s.description }}</p>
        </div>
        <span class="text-body-main text-n-slate-11">{{ statusLabel(s.status) }}</span>
        <Button v-if="s.status === 'pending_review'" size="sm" :label="t('RAGENT.SKILLS.APPROVE')" @click="skillAct(s, 'approve')" />
        <Button v-if="s.status === 'pending_review'" size="sm" variant="faded" :label="t('RAGENT.SKILLS.DISCARD')" @click="skillAct(s, 'discard')" />
        <Button v-if="s.status === 'approved'" size="sm" variant="faded" :label="t('RAGENT.SKILLS.DISABLE')" @click="skillAct(s, 'disable')" />
        <Button v-if="s.status === 'disabled'" size="sm" :label="t('RAGENT.SKILLS.ENABLE')" @click="skillAct(s, 'enable')" />
      </li>
      <li v-if="!skills.length && !loading" class="px-4 py-6 text-n-slate-11">{{ t('RAGENT.SKILLS.EMPTY') }}</li>
    </ul>

    <ul v-if="tab === 'routines'" class="divide-y divide-n-weak rounded-xl border border-n-weak">
      <li v-for="r in routines" :key="r.id" class="flex items-center gap-3 px-4 py-3">
        <div class="min-w-0 flex-1">
          <p class="truncate text-body-main text-n-slate-12">{{ r.name }}</p>
          <p class="truncate text-body-main text-n-slate-11">{{ r.cron }} · {{ r.timezone }}</p>
        </div>
        <span class="text-body-main text-n-slate-11">{{ statusLabel(r.status) }}</span>
        <Button v-if="r.status === 'active'" size="sm" variant="faded" :label="t('RAGENT.SKILLS.PAUSE')" @click="routineAct(r, 'pause')" />
        <Button v-else size="sm" :label="t('RAGENT.SKILLS.RESUME')" @click="routineAct(r, 'resume')" />
        <Button size="sm" color="ruby" :label="t('RAGENT.SKILLS.DELETE')" @click="routineDelete(r)" />
      </li>
      <li v-if="!routines.length && !loading" class="px-4 py-6 text-n-slate-11">{{ t('RAGENT.SKILLS.EMPTY_ROUTINES') }}</li>
    </ul>

    <ul v-if="tab === 'memories'" class="divide-y divide-n-weak rounded-xl border border-n-weak">
      <li v-for="p in proposals" :key="p.id" class="flex items-center gap-3 px-4 py-3">
        <p class="min-w-0 flex-1 text-body-main text-n-slate-12">{{ p.content || p.text }}</p>
        <Button size="sm" :label="t('RAGENT.SKILLS.APPROVE')" @click="memoryAct(p, 'approve')" />
        <Button size="sm" variant="faded" :label="t('RAGENT.SKILLS.DISCARD')" @click="memoryAct(p, 'discard')" />
      </li>
      <li v-if="!proposals.length && !loading" class="px-4 py-6 text-n-slate-11">{{ t('RAGENT.SKILLS.EMPTY_MEMORIES') }}</li>
    </ul>
  </div>
</template>
