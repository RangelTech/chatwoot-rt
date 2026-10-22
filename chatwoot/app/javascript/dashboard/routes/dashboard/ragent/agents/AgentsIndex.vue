<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import rtAiAgents from 'dashboard/api/rtAiAgents';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const agents = ref([]);
const loading = ref(true);
const forbidden = ref(false);
const creating = ref(false);
const newName = ref('');
const newDescription = ref('');
const editing = ref(null);
const files = ref([]);
const versions = ref([]);
const manifest = ref({ tools: [] });
const combos = ref([]);
const selectedCombo = ref('');
const legacyModelAlias = ref('');
// Spec 11 §4: o agente escolhe skills da empresa (checkbox); o campo "Ferramentas" saiu.
const hostOptions = ref([]);
const linkedHostIds = ref([]);
const skillOptions = ref([]);
const linkedSkillIds = ref([]);
const skillsBase = () => `/api/v1/accounts/${window.location.pathname.split('/')[3]}/rt_ai/skills/agent`;
const hostsBase = () =>
  `/api/v1/accounts/${window.location.pathname.split('/')[3]}/rt_ai/hosts/agent`;
const loadHostLinks = async id => {
  try {
    const { data } = await window.axios.get(`${hostsBase()}/${id}`);
    hostOptions.value = data.hosts || [];
    linkedHostIds.value = hostOptions.value.filter(x => x.linked).map(x => x.id);
  } catch (error) {
    hostOptions.value = [];
    linkedHostIds.value = [];
  }
};
const loadSkillLinks = async id => {
  try {
    const { data } = await window.axios.get(`${skillsBase()}/${id}`);
    skillOptions.value = data.skills || [];
    linkedSkillIds.value = skillOptions.value.filter(x => x.linked).map(x => x.id);
  } catch (error) {
    skillOptions.value = [];
    linkedSkillIds.value = [];
  }
};
const confirmActions = ref(false);
const allowLuar = ref(false);
const OUTPUT_FORMATS = ['markdown', 'whatsapp', 'text'];
const outputFormat = ref('markdown');
const problems = ref([]);
const busy = ref(false);
const fileError = ref('');
const fileInput = ref(null);
const replaceTarget = ref(null);

const visibleAgents = computed(() =>
  agents.value.filter(
    a => (!a.system_key || a.system_key === 'moon') && a.agent_kind === 'skills'
  )
);

const load = async () => {
  try {
    const { data } = await rtAiAgents.get();
    agents.value = data.items || data || [];
  } catch (error) {
    forbidden.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(load);

const create = async () => {
  if (!newName.value.trim()) return;
  busy.value = true;
  try {
    await rtAiAgents.create({
      name: newName.value.trim(),
      description: newDescription.value.trim(),
      agent_kind: 'skills',
    });
    newName.value = '';
    newDescription.value = '';
    creating.value = false;
    await load();
  } catch (error) {
    useAlert(t('RAGENT.AGENTS.ERROR'));
  } finally {
    busy.value = false;
  }
};

const edit = async agent => {
  const { data } = await rtAiAgents.draft(agent.id);
  editing.value = agent;
  files.value = data.files || [];
  manifest.value = data.manifest || { tools: [] };
  try {
    const comboResponse = await rtAiAgents.combos();
    combos.value = Array.isArray(comboResponse.data)
      ? comboResponse.data
      : comboResponse.data.combos || [];
  } catch (error) {
    combos.value = [];
    useAlert(t('RAGENT.AGENTS.ERROR'));
  }
  selectedCombo.value = manifest.value.model?.combo || '';
  legacyModelAlias.value = manifest.value.model?.alias || '';
  await loadSkillLinks(agent.id);
  await loadHostLinks(agent.id);
  confirmActions.value = Boolean(manifest.value.limits?.confirm_actions);
  allowLuar.value = Boolean(manifest.value.limits?.luar);
  outputFormat.value = OUTPUT_FORMATS.includes(manifest.value.output?.format)
    ? manifest.value.output.format
    : 'markdown';
  problems.value = [];
  fileError.value = '';
  try {
    versions.value = (await rtAiAgents.versions(agent.id)).data || [];
  } catch (error) {
    versions.value = [];
  }
};

// Rollback: versões são imutáveis; voltar é publicar de novo uma versão antiga.
const restore = async version => {
  busy.value = true;
  try {
    await rtAiAgents.publish(editing.value.id, version.id);
    useAlert(t('RAGENT.AGENTS.RESTORED', { n: version.number }));
    editing.value = null;
    await load();
  } catch (error) {
    useAlert(t('RAGENT.AGENTS.ERROR'));
  } finally {
    busy.value = false;
  }
};

const mainFile = computed(
  () => files.value.find(f => f.path === 'AGENTE.md') || files.value[0]
);

// Arquivos da pasta arquivos/ (binários) têm rotas próprias; o rascunho de texto não os leva.
const assets = computed(() => files.value.filter(f => f.kind === 'asset'));

const payload = () => ({
  files: files.value
    .filter(f => f.kind !== 'asset')
    .map(f => ({ path: f.path, content: f.content })),
  manifest: {
    ...manifest.value,
    model: selectedCombo.value
      ? { combo: selectedCombo.value }
      : legacyModelAlias.value
        ? { alias: legacyModelAlias.value }
        : null,
    output: { format: outputFormat.value },
    limits: {
      ...(manifest.value.limits || {}),
      confirm_actions: confirmActions.value,
      luar: allowLuar.value,
    },
    tools: manifest.value.tools || [],
  },
});

const save = async () => {
  busy.value = true;
  try {
    await window.axios.put(`${hostsBase()}/${editing.value.id}`, {
      host_ids: linkedHostIds.value,
    });
    await window.axios.put(`${skillsBase()}/${editing.value.id}`, {
      skill_ids: linkedSkillIds.value,
    });
    const { data } = await rtAiAgents.saveDraft(editing.value.id, payload());
    problems.value = data.problems || [];
    useAlert(t('RAGENT.AGENTS.SAVED'));
  } catch (error) {
    useAlert(t('RAGENT.AGENTS.ERROR'));
  } finally {
    busy.value = false;
  }
};

const fileName = path => path.split('/').slice(1).join('/');

const fileSize = bytes => {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
};

const pickFile = path => {
  replaceTarget.value = path;
  fileInput.value?.click();
};

const upsertAsset = asset => {
  const index = files.value.findIndex(f => f.path === asset.path);
  if (index >= 0) files.value.splice(index, 1, asset);
  else files.value.push(asset);
};

const onFilePicked = async event => {
  const [file] = event.target.files || [];
  event.target.value = '';
  if (!file) return;
  fileError.value = '';
  busy.value = true;
  try {
    const { data } = await rtAiAgents.uploadFile(
      editing.value.id,
      file,
      replaceTarget.value
    );
    upsertAsset({ ...data, kind: 'asset' });
    useAlert(t('RAGENT.AGENTS.FILES.SAVED'));
  } catch (error) {
    fileError.value =
      error.response?.data?.message || t('RAGENT.AGENTS.FILES.ERROR');
  } finally {
    replaceTarget.value = null;
    busy.value = false;
  }
};

const removeFile = async asset => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAGENT.AGENTS.FILES.CONFIRM_REMOVE'))) return;
  fileError.value = '';
  busy.value = true;
  try {
    await rtAiAgents.deleteFile(editing.value.id, asset.path);
    files.value = files.value.filter(f => f.path !== asset.path);
  } catch (error) {
    fileError.value =
      error.response?.data?.message || t('RAGENT.AGENTS.FILES.ERROR');
  } finally {
    busy.value = false;
  }
};

const publish = async () => {
  busy.value = true;
  try {
    const checked = await rtAiAgents.validate(editing.value.id, payload());
    problems.value = checked.data.problems || [];
    if (!checked.data.ok) return;
    await rtAiAgents.saveDraft(editing.value.id, payload());
    const version = await rtAiAgents.createVersion(editing.value.id);
    await rtAiAgents.publish(editing.value.id, version.data.id);
    useAlert(t('RAGENT.AGENTS.PUBLISHED'));
    editing.value = null;
    await load();
  } catch (error) {
    useAlert(t('RAGENT.AGENTS.ERROR'));
  } finally {
    busy.value = false;
  }
};

const archive = async agent => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAGENT.AGENTS.CONFIRM_ARCHIVE'))) return;
  await rtAiAgents.archive(agent.id);
  await load();
};
</script>

<template>
  <div class="mx-auto flex h-full w-full max-w-5xl flex-col gap-4 overflow-y-auto p-6">
    <header class="flex items-center gap-3">
      <h1 class="text-heading-1 text-n-slate-12">
        {{ t('RAGENT.AGENTS.TITLE') }}
      </h1>
      <Button
        v-if="!editing"
        class="ms-auto"
        :label="t('RAGENT.AGENTS.NEW')"
        @click="creating = !creating"
      />
    </header>

    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="forbidden" class="text-n-slate-11">
      {{ t('RAGENT.CHAT.FORBIDDEN') }}
    </p>

    <section v-if="creating && !editing" class="flex flex-col gap-2 rounded-xl border border-n-weak p-4">
      <input v-model="newName" type="text" :placeholder="t('RAGENT.AGENTS.NAME')" />
      <input
        v-model="newDescription"
        type="text"
        :placeholder="t('RAGENT.AGENTS.DESCRIPTION')"
      />
      <Button :label="t('RAGENT.AGENTS.CREATE')" :disabled="busy" @click="create" />
    </section>

    <ul v-if="!editing" class="divide-y divide-n-weak rounded-xl border border-n-weak">
      <li
        v-for="a in visibleAgents"
        :key="a.id"
        class="flex items-center gap-3 px-4 py-3"
      >
        <div class="min-w-0 flex-1">
          <p class="truncate text-body-main text-n-slate-12">{{ a.name }}</p>
          <p class="truncate text-body-main text-n-slate-11">
            {{ a.description }}
          </p>
        </div>
        <span class="text-body-main text-n-slate-11">
          {{
            a.active_version_number
              ? t('RAGENT.AGENTS.VERSION', { n: a.active_version_number })
              : t('RAGENT.AGENTS.DRAFT')
          }}
        </span>
        <span v-if="a.system_key === 'moon'" class="text-body-main text-n-slate-11">
          {{ t('RAGENT.AGENTS.MOON_FIXED') }}
        </span>
        <template v-else>
          <Button size="sm" :label="t('RAGENT.AGENTS.EDIT')" @click="edit(a)" />
          <Button
            size="sm"
            color="ruby"
            :label="t('RAGENT.AGENTS.ARCHIVE')"
            @click="archive(a)"
          />
        </template>
      </li>
      <li v-if="!visibleAgents.length && !loading" class="px-4 py-6 text-n-slate-11">
        {{ t('RAGENT.AGENTS.EMPTY') }}
      </li>
    </ul>

    <section v-if="editing" class="flex flex-col gap-3">
      <h2 class="text-heading-2 text-n-slate-12">{{ editing.name }}</h2>
      <label class="text-body-main text-n-slate-11">
        {{ t('RAGENT.AGENTS.INSTRUCTIONS') }}
        <textarea
          v-if="mainFile"
          v-model="mainFile.content"
          rows="16"
          class="!mb-0 w-full font-mono"
        />
      </label>
      <fieldset class="flex flex-col gap-1 text-body-main text-n-slate-11">
        <legend class="mb-1">{{ t('RAGENT.AGENTS.SKILLS') }}</legend>
        <p v-if="!skillOptions.length" class="text-n-slate-10">
          {{ t('RAGENT.AGENTS.SKILLS_EMPTY') }}
        </p>
        <label
          v-for="sk in skillOptions"
          :key="sk.id"
          class="flex items-center gap-2"
        >
          <input v-model="linkedSkillIds" type="checkbox" :value="sk.id" class="!mb-0" />
          <span class="text-n-slate-12">{{ sk.name }}</span>
          <span v-if="sk.files" class="text-n-slate-10">
            ({{ t('RAGENT.AGENTS.SKILL_FILES', { n: sk.files }) }})
          </span>
        </label>
      </fieldset>
      <fieldset
        v-if="hostOptions.length"
        class="flex flex-col gap-1 text-body-main text-n-slate-11"
      >
        <legend class="mb-1">{{ t('RAGENT.HOSTS.AGENT_HOSTS') }}</legend>
        <label v-for="h in hostOptions" :key="h.id" class="flex items-center gap-2">
          <input v-model="linkedHostIds" type="checkbox" :value="h.id" class="!mb-0" />
          <span class="text-n-slate-12">{{ h.name }}</span>
        </label>
      </fieldset>
      <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.AGENTS.MODEL_COMBO') }}
        <select
          v-model="selectedCombo"
          class="!mb-0 w-full max-w-md"
          data-testid="model-combo"
        >
          <option value="">{{ t('RAGENT.AGENTS.MODEL_COMBO_DEFAULT') }}</option>
          <option v-for="combo in combos" :key="combo.name" :value="combo.name">
            {{ combo.name }}
          </option>
        </select>
        <span>{{ t('RAGENT.AGENTS.MODEL_COMBO_HELP') }}</span>
      </label>
      <label class="flex items-center gap-2 text-body-main text-n-slate-11">
        <input v-model="confirmActions" type="checkbox" class="!mb-0" />
        {{ t('RAGENT.AGENTS.CONFIRM_ACTIONS') }}
      </label>
      <label class="flex items-center gap-2 text-body-main text-n-slate-11">
        <input v-model="allowLuar" type="checkbox" class="!mb-0" />
        {{ t('RAGENT.AGENTS.ALLOW_LUAR') }}
      </label>
      <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.AGENTS.OUTPUT_FORMAT') }}
        <select
          v-model="outputFormat"
          class="!mb-0 w-full max-w-md"
          data-testid="output-format"
        >
          <option v-for="f in OUTPUT_FORMATS" :key="f" :value="f">
            {{ t(`RAGENT.AGENTS.OUTPUT_FORMATS.${f.toUpperCase()}`) }}
          </option>
        </select>
        <span>{{ t('RAGENT.AGENTS.OUTPUT_FORMAT_HELP') }}</span>
      </label>
      <section class="flex flex-col gap-2 rounded-xl border border-n-weak p-3">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('RAGENT.AGENTS.FILES.TITLE') }}
        </h3>
        <p class="text-body-main text-n-slate-11">
          {{ t('RAGENT.AGENTS.FILES.HELP') }}
        </p>
        <ul
          v-if="assets.length"
          class="divide-y divide-n-weak rounded-lg border border-n-weak"
        >
          <li
            v-for="f in assets"
            :key="f.path"
            class="flex items-center gap-3 px-3 py-2"
          >
            <span class="min-w-0 flex-1 truncate text-body-main text-n-slate-12">
              {{ fileName(f.path) }}
            </span>
            <span class="text-body-main text-n-slate-11">
              {{ fileSize(f.size_bytes) }} · {{ f.mime }}
            </span>
            <Button
              size="sm"
              variant="faded"
              :disabled="busy"
              :label="t('RAGENT.AGENTS.FILES.REPLACE')"
              @click="pickFile(f.path)"
            />
            <Button
              size="sm"
              color="ruby"
              :disabled="busy"
              :label="t('RAGENT.AGENTS.FILES.REMOVE')"
              @click="removeFile(f)"
            />
          </li>
        </ul>
        <p v-else class="text-body-main text-n-slate-11">
          {{ t('RAGENT.AGENTS.FILES.EMPTY') }}
        </p>
        <p
          v-if="fileError"
          role="alert"
          class="rounded-lg border border-n-ruby-9 p-2 text-body-main text-n-ruby-11"
        >
          {{ fileError }}
        </p>
        <input
          ref="fileInput"
          type="file"
          class="hidden"
          data-testid="package-file-input"
          @change="onFilePicked"
        />
        <div>
          <Button
            size="sm"
            :disabled="busy"
            :label="t('RAGENT.AGENTS.FILES.UPLOAD')"
            @click="pickFile(null)"
          />
        </div>
      </section>
      <section v-if="versions.length" class="flex flex-col gap-2 rounded-xl border border-n-weak p-3">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('RAGENT.AGENTS.VERSIONS') }}
        </h3>
        <ul class="flex flex-col gap-1">
          <li v-for="v in versions" :key="v.id" class="flex items-center gap-2 text-body-main text-n-slate-11">
            <span>{{ t('RAGENT.AGENTS.VERSION', { n: v.number }) }}</span>
            <span v-if="v.id === editing.active_version_id" class="text-n-teal-11">{{ t('RAGENT.AGENTS.ACTIVE') }}</span>
            <Button
              v-else
              size="sm"
              variant="faded"
              :label="t('RAGENT.AGENTS.RESTORE')"
              :disabled="busy"
              @click="restore(v)"
            />
          </li>
        </ul>
      </section>
      <ul v-if="problems.length" class="rounded-lg border border-n-ruby-9 p-3 text-body-main text-n-ruby-11">
        <li v-for="(p, i) in problems" :key="i">
          {{ p.file ? `${p.file}: ` : '' }}{{ p.message }}
        </li>
      </ul>
      <div class="flex gap-2">
        <Button :label="t('RAGENT.AGENTS.SAVE')" :disabled="busy" @click="save" />
        <Button :label="t('RAGENT.AGENTS.PUBLISH')" :disabled="busy" @click="publish" />
        <Button
          variant="faded"
          :label="t('RAGENT.AGENTS.BACK')"
          @click="editing = null"
        />
      </div>
    </section>
  </div>
</template>
