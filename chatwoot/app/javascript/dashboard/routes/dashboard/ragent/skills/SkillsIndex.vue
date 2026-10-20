<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import SkillForm from './SkillForm.vue';
import RoutineForm from './RoutineForm.vue';
import { describeCron } from './skillText';

const { axios } = window;
const { t } = useI18n();
const route = useRoute();
const base = `/api/v1/accounts/${route.params.accountId}/rt_ai`;

const tab = ref('company');
const companySkills = ref([]);
const mySkills = ref([]);
const routines = ref([]);
const proposals = ref([]);
const templates = ref([]);
const scopes = ref([]);
const loading = ref(true);
const forbidden = ref(false);
// 'skill-company' | 'skill-mine' | 'routine' | null, e o item sendo editado
const form = ref(null);
const history = ref({});

const list = data =>
  data?.items || data?.schedules || data?.skills || data || [];

const can = scope => scopes.value.includes(scope);
const canManageCompany = computed(
  () => can('ai.skills.manage_company') || can('ai.agents.edit')
);
const canManageOwn = computed(() => can('ai.skills.manage_own'));
const canManageRoutines = computed(() => can('ai.routines.manage'));

const safe = async (request, fallback) => {
  try {
    return (await request()).data;
  } catch (error) {
    return fallback;
  }
};

const load = async () => {
  loading.value = true;
  forbidden.value = false;
  try {
    const [me, company, mine, routs] = await Promise.all([
      axios.get(`${base}/me`),
      axios.get(`${base}/skills/company`),
      axios.get(`${base}/skills`),
      axios.get(`${base}/skills/routines`),
    ]);
    scopes.value = me.data.scopes || [];
    companySkills.value = list(company.data);
    mySkills.value = list(mine.data);
    routines.value = list(routs.data);
  } catch (error) {
    forbidden.value = true;
  }
  proposals.value = list(
    await safe(() => axios.get(`${base}/skills/memory_proposals`), [])
  );
  templates.value = await safe(() => axios.get(`${base}/chats/templates`), []);
  loading.value = false;
};
onMounted(load);

const run = async (verb, url) => {
  try {
    await axios[verb](url);
    await load();
  } catch (error) {
    useAlert(error.response?.data?.message || t('RAGENT.SKILLS.ERROR'));
  }
};

const confirmed = key => window.confirm(t(key));

const skillAct = (s, action) =>
  run('post', `${base}/skills/${s.id}/act/${action}`);
const skillDelete = s =>
  confirmed('RAGENT.SKILLS.CONFIRM_DELETE') &&
  run('delete', `${base}/skills/${s.id}`);
const companyAct = (s, action) =>
  run('post', `${base}/skills/company/${s.id}/act/${action}`);
const companyDelete = s =>
  confirmed('RAGENT.SKILLS.CONFIRM_DELETE_COMPANY') &&
  run('delete', `${base}/skills/company/${s.id}`);
const routineAct = (r, action) =>
  run('post', `${base}/routines/${r.id}/${action}`);
const routineDelete = r =>
  confirmed('RAGENT.ROUTINE.CONFIRM_DELETE') &&
  run('delete', `${base}/routines/${r.id}`);
const memoryAct = (p, action) =>
  run('post', `${base}/memory_proposals/${p.id}/${action}`);

const closeForm = async () => {
  form.value = null;
  await load();
};

const toggleHistory = async r => {
  if (history.value[r.id]) {
    history.value = { ...history.value, [r.id]: null };
    return;
  }
  const data = await safe(() => axios.get(`${base}/routines/${r.id}/runs`), {
    runs: [],
  });
  history.value = { ...history.value, [r.id]: data.runs || [] };
};

const dayNames = computed(() => t('RAGENT.ROUTINE.DAYS').split(','));
const describe = cron => describeCron(cron, t, dayNames.value);
const when = iso =>
  iso
    ? new Date(iso).toLocaleString(undefined, {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';
const statusLabel = s => t(`RAGENT.SKILLS.STATUS.${String(s).toUpperCase()}`);
const runLabel = s => t(`RAGENT.ROUTINE.RUN.${String(s).toUpperCase()}`);
const chatPath = id =>
  `/app/accounts/${route.params.accountId}/ragent/chat/${id}`;

const pkgSkills = computed(() =>
  companySkills.value.filter(s => s.scope === 'template')
);
// Pacote publicado de cada agente: AGENTE.md + skills/*/SKILL.md, agrupado por agente.
const agentGroups = computed(() => {
  const groups = new Map();
  pkgSkills.value.forEach(s => {
    if (!groups.has(s.template_id)) {
      groups.set(s.template_id, {
        id: s.template_id,
        name: s.template_name,
        agentFile: null,
        skills: [],
      });
    }
    const group = groups.get(s.template_id);
    if (s.kind === 'agent') group.agentFile = s;
    else group.skills.push(s);
  });
  return [...groups.values()];
});
const agentsPath = computed(
  () => `/app/accounts/${route.params.accountId}/ragent/agents`
);
const sharedSkills = computed(() =>
  companySkills.value.filter(s => s.scope === 'company')
);

const tabs = computed(() => [
  {
    key: 'company',
    label: t('RAGENT.SKILLS.COMPANY'),
    count: companySkills.value.filter(s => s.kind !== 'agent').length,
  },
  { key: 'mine', label: t('RAGENT.SKILLS.MINE'), count: mySkills.value.length },
  {
    key: 'routines',
    label: t('RAGENT.SKILLS.ROUTINES'),
    count: routines.value.length,
  },
  {
    key: 'memories',
    label: t('RAGENT.SKILLS.MEMORIES'),
    count: proposals.value.length,
  },
]);
</script>

<template>
  <div
    class="mx-auto flex h-full w-full max-w-5xl flex-col gap-4 overflow-y-auto p-6"
  >
    <h1 class="text-heading-1 text-n-slate-12">
      {{ t('RAGENT.SKILLS.TITLE') }}
    </h1>
    <nav class="flex flex-wrap gap-2 border-b border-n-weak">
      <button
        v-for="x in tabs"
        :key="x.key"
        type="button"
        class="px-3 py-2 text-body-main"
        :class="
          tab === x.key
            ? 'border-b-2 border-n-brand text-n-slate-12'
            : 'text-n-slate-11'
        "
        @click="
          tab = x.key;
          form = null;
        "
      >
        {{ x.label }} ({{ x.count }})
      </button>
    </nav>

    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="forbidden" class="text-n-slate-11">
      {{ t('RAGENT.CHAT.FORBIDDEN') }}
    </p>

    <!-- Da empresa -->
    <template v-if="tab === 'company' && !loading && !forbidden">
      <SkillForm
        v-if="form?.type === 'skill-company'"
        scope="company"
        :base="base"
        :skill="form.item"
        @saved="closeForm"
        @cancel="form = null"
      />
      <template v-else>
        <div class="flex flex-wrap items-center gap-3">
          <p class="min-w-0 flex-1 text-body-main text-n-slate-11">
            {{ t('RAGENT.SKILLS.COMPANY_HELP') }}
          </p>
          <Button
            v-if="canManageCompany"
            size="sm"
            :label="t('RAGENT.SKILLS.NEW_COMPANY')"
            @click="form = { type: 'skill-company', item: null }"
          />
        </div>
        <ul class="divide-y divide-n-weak rounded-xl border border-n-weak">
          <li
            v-for="s in sharedSkills"
            :key="s.id"
            class="flex flex-wrap items-center gap-3 px-4 py-3"
          >
            <div class="min-w-0 flex-1">
              <p class="truncate text-body-main text-n-slate-12">
                {{ s.name }}
              </p>
              <p class="truncate text-body-main text-n-slate-11">
                {{ s.description }}
              </p>
            </div>
            <span class="text-body-main text-n-slate-11">{{
              statusLabel(s.status)
            }}</span>
            <template v-if="canManageCompany">
              <Button
                size="sm"
                variant="faded"
                :label="t('RAGENT.SKILLS.EDIT')"
                @click="form = { type: 'skill-company', item: s }"
              />
              <Button
                v-if="s.status === 'active'"
                size="sm"
                variant="faded"
                :label="t('RAGENT.SKILLS.DISABLE')"
                @click="companyAct(s, 'disable')"
              />
              <Button
                v-else
                size="sm"
                :label="t('RAGENT.SKILLS.ENABLE')"
                @click="companyAct(s, 'enable')"
              />
              <Button
                size="sm"
                color="ruby"
                :label="t('RAGENT.SKILLS.DELETE_ITEM')"
                @click="companyDelete(s)"
              />
            </template>
          </li>
          <li v-if="!sharedSkills.length" class="px-4 py-4 text-n-slate-11">
            {{ t('RAGENT.SKILLS.EMPTY_SHARED') }}
          </li>
        </ul>

        <section
          v-for="g in agentGroups"
          :key="g.id"
          class="rounded-xl border border-n-weak"
          data-testid="agent-package"
        >
          <header class="flex flex-wrap items-center gap-3 px-4 py-3">
            <h2 class="min-w-0 flex-1 truncate text-heading-3 text-n-slate-12">
              {{ t('RAGENT.SKILLS.AGENT_PACKAGE', { agent: g.name }) }}
            </h2>
            <a
              :href="agentsPath"
              class="text-body-main text-n-brand hover:underline"
            >
              {{ t('RAGENT.SKILLS.OPEN_AGENT') }}
            </a>
          </header>
          <ul class="divide-y divide-n-weak border-t border-n-weak">
            <li v-if="g.agentFile" class="flex flex-col gap-1 px-4 py-3">
              <p class="text-body-main text-n-slate-12">
                {{ t('RAGENT.SKILLS.AGENT_FILE') }}
              </p>
              <p class="text-body-main text-n-slate-11">
                {{ g.agentFile.description }}
              </p>
            </li>
            <li
              v-for="s in g.skills"
              :key="`${g.id}-${s.name}`"
              class="flex flex-col gap-1 px-4 py-3"
            >
              <p class="truncate text-body-main text-n-slate-12">
                {{ s.name }}
              </p>
              <p class="truncate text-body-main text-n-slate-11">
                {{ s.description }}
              </p>
            </li>
            <li v-if="!g.skills.length" class="px-4 py-3 text-n-slate-11">
              {{ t('RAGENT.SKILLS.EMPTY_PACKAGE') }}
            </li>
          </ul>
        </section>

        <div
          v-if="!companySkills.length"
          class="rounded-xl border border-dashed border-n-weak px-4 py-6 text-n-slate-11"
          data-testid="company-empty"
        >
          <p class="text-body-main text-n-slate-12">
            {{ t('RAGENT.SKILLS.EMPTY_COMPANY') }}
          </p>
          <p class="mt-1 text-body-main">
            {{ t('RAGENT.SKILLS.EMPTY_COMPANY_WHY') }}
          </p>
        </div>
        <p v-if="pkgSkills.length" class="text-xs text-n-slate-10">
          {{ t('RAGENT.SKILLS.PACKAGE_HINT') }}
        </p>
      </template>
    </template>

    <!-- Minhas -->
    <template v-if="tab === 'mine' && !loading && !forbidden">
      <SkillForm
        v-if="form?.type === 'skill-mine'"
        scope="mine"
        :base="base"
        :skill="form.item"
        @saved="closeForm"
        @cancel="form = null"
      />
      <template v-else>
        <div class="flex flex-wrap items-center gap-3">
          <p class="min-w-0 flex-1 text-body-main text-n-slate-11">
            {{ t('RAGENT.SKILLS.MINE_HELP') }}
          </p>
          <Button
            v-if="canManageOwn"
            size="sm"
            :label="t('RAGENT.SKILLS.NEW_MINE')"
            @click="form = { type: 'skill-mine', item: null }"
          />
        </div>
        <ul class="divide-y divide-n-weak rounded-xl border border-n-weak">
          <li
            v-for="s in mySkills"
            :key="s.id"
            class="flex flex-wrap items-center gap-3 px-4 py-3"
          >
            <div class="min-w-0 flex-1">
              <p class="truncate text-body-main text-n-slate-12">
                {{ s.name }}
              </p>
              <p class="truncate text-body-main text-n-slate-11">
                {{ s.description }}
              </p>
            </div>
            <span class="text-body-main text-n-slate-11">{{
              statusLabel(s.status)
            }}</span>
            <template v-if="canManageOwn">
              <Button
                v-if="s.status === 'pending_review'"
                size="sm"
                :label="t('RAGENT.SKILLS.APPROVE')"
                @click="skillAct(s, 'approve')"
              />
              <Button
                v-if="s.status === 'pending_review'"
                size="sm"
                variant="faded"
                :label="t('RAGENT.SKILLS.DISCARD')"
                @click="skillAct(s, 'discard')"
              />
              <Button
                v-if="s.status === 'active'"
                size="sm"
                variant="faded"
                :label="t('RAGENT.SKILLS.DISABLE')"
                @click="skillAct(s, 'disable')"
              />
              <Button
                v-if="s.status === 'disabled'"
                size="sm"
                :label="t('RAGENT.SKILLS.ENABLE')"
                @click="skillAct(s, 'enable')"
              />
              <Button
                size="sm"
                variant="faded"
                :label="t('RAGENT.SKILLS.EDIT')"
                @click="form = { type: 'skill-mine', item: s }"
              />
              <Button
                size="sm"
                color="ruby"
                :label="t('RAGENT.SKILLS.DELETE_ITEM')"
                @click="skillDelete(s)"
              />
            </template>
          </li>
          <li v-if="!mySkills.length" class="px-4 py-6 text-n-slate-11">
            {{ t('RAGENT.SKILLS.EMPTY') }}
          </li>
        </ul>
      </template>
    </template>

    <!-- Rotinas -->
    <template v-if="tab === 'routines' && !loading && !forbidden">
      <RoutineForm
        v-if="form?.type === 'routine'"
        :base="base"
        :templates="templates"
        :routine="form.item"
        @saved="closeForm"
        @cancel="form = null"
      />
      <template v-else>
        <div class="flex flex-wrap items-center gap-3">
          <p class="min-w-0 flex-1 text-body-main text-n-slate-11">
            {{ t('RAGENT.ROUTINE.HELP') }}
          </p>
          <Button
            v-if="canManageRoutines && templates.length"
            size="sm"
            :label="t('RAGENT.ROUTINE.NEW')"
            @click="form = { type: 'routine', item: null }"
          />
        </div>
        <p
          v-if="canManageRoutines && !templates.length"
          class="text-body-main text-n-slate-11"
        >
          {{ t('RAGENT.ROUTINE.NO_AGENT') }}
        </p>
        <ul class="divide-y divide-n-weak rounded-xl border border-n-weak">
          <li
            v-for="r in routines"
            :key="r.id"
            class="flex flex-col gap-2 px-4 py-3"
          >
            <div class="flex flex-wrap items-center gap-3">
              <div class="min-w-0 flex-1">
                <p class="truncate text-body-main text-n-slate-12">
                  {{ r.name }}
                </p>
                <p class="truncate text-body-main text-n-slate-11">
                  {{ describe(r.cron) }} · {{ r.timezone }}
                  <template v-if="r.template_name">
                    · {{ r.template_name }}
                  </template>
                </p>
                <p class="truncate text-xs text-n-slate-10">
                  <template v-if="r.status === 'active' && r.next_run_at">
                    {{
                      t('RAGENT.ROUTINE.NEXT', { when: when(r.next_run_at) })
                    }}
                  </template>
                  <template v-else>
                    {{ t('RAGENT.ROUTINE.NOT_SCHEDULED') }}
                  </template>
                  <template v-if="r.last_run_at">
                    ·
                    {{
                      t('RAGENT.ROUTINE.LAST', {
                        when: when(r.last_run_at),
                        status: runLabel(r.last_status || 'running'),
                      })
                    }}
                  </template>
                </p>
              </div>
              <span class="text-body-main text-n-slate-11">{{
                statusLabel(r.status)
              }}</span>
              <Button
                size="sm"
                variant="faded"
                :label="t('RAGENT.ROUTINE.HISTORY')"
                @click="toggleHistory(r)"
              />
              <template v-if="canManageRoutines">
                <Button
                  size="sm"
                  variant="faded"
                  :label="t('RAGENT.SKILLS.EDIT')"
                  @click="form = { type: 'routine', item: r }"
                />
                <Button
                  v-if="r.status === 'active'"
                  size="sm"
                  variant="faded"
                  :label="t('RAGENT.SKILLS.PAUSE')"
                  @click="routineAct(r, 'pause')"
                />
                <Button
                  v-else
                  size="sm"
                  :label="t('RAGENT.SKILLS.RESUME')"
                  @click="routineAct(r, 'resume')"
                />
                <Button
                  size="sm"
                  color="ruby"
                  :label="t('RAGENT.SKILLS.DELETE')"
                  @click="routineDelete(r)"
                />
              </template>
            </div>
            <ul
              v-if="history[r.id]"
              class="divide-y divide-n-weak rounded-lg border border-n-weak"
            >
              <li
                v-for="h in history[r.id]"
                :key="h.id"
                class="flex flex-wrap items-center gap-3 px-3 py-2 text-body-main"
              >
                <span class="text-n-slate-12">{{ when(h.started_at) }}</span>
                <span class="flex-1 text-n-slate-11">{{
                  runLabel(h.status)
                }}</span>
                <a
                  v-if="h.chat_id"
                  :href="chatPath(h.chat_id)"
                  class="text-n-brand"
                  >{{ t('RAGENT.ROUTINE.OPEN_CHAT') }}</a
                >
              </li>
              <li
                v-if="!history[r.id].length"
                class="px-3 py-2 text-n-slate-11"
              >
                {{ t('RAGENT.ROUTINE.NO_RUNS') }}
              </li>
            </ul>
          </li>
          <li v-if="!routines.length" class="px-4 py-6 text-n-slate-11">
            {{ t('RAGENT.SKILLS.EMPTY_ROUTINES') }}
          </li>
        </ul>
      </template>
    </template>

    <!-- Memória -->
    <ul
      v-if="tab === 'memories' && !loading && !forbidden"
      class="divide-y divide-n-weak rounded-xl border border-n-weak"
    >
      <li
        v-for="p in proposals"
        :key="p.id"
        class="flex items-center gap-3 px-4 py-3"
      >
        <p class="min-w-0 flex-1 text-body-main text-n-slate-12">
          {{ p.content || p.text }}
        </p>
        <Button
          size="sm"
          :label="t('RAGENT.SKILLS.APPROVE')"
          @click="memoryAct(p, 'approve')"
        />
        <Button
          size="sm"
          variant="faded"
          :label="t('RAGENT.SKILLS.DISCARD')"
          @click="memoryAct(p, 'discard')"
        />
      </li>
      <li v-if="!proposals.length" class="px-4 py-6 text-n-slate-11">
        {{ t('RAGENT.SKILLS.EMPTY_MEMORIES') }}
      </li>
    </ul>
  </div>
</template>
