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
const manifest = ref({ tools: [] });
const toolsText = ref('');
const problems = ref([]);
const busy = ref(false);

const visibleAgents = computed(() =>
  agents.value.filter(a => !a.system_key && a.agent_kind === 'skills')
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
  toolsText.value = (manifest.value.tools || []).join(', ');
  problems.value = [];
};

const mainFile = computed(
  () => files.value.find(f => f.path === 'AGENTE.md') || files.value[0]
);

const payload = () => ({
  files: files.value.map(f => ({ path: f.path, content: f.content })),
  manifest: {
    ...manifest.value,
    tools: toolsText.value
      .split(',')
      .map(x => x.trim())
      .filter(Boolean),
  },
});

const save = async () => {
  busy.value = true;
  try {
    const { data } = await rtAiAgents.saveDraft(editing.value.id, payload());
    problems.value = data.problems || [];
    useAlert(t('RAGENT.AGENTS.SAVED'));
  } catch (error) {
    useAlert(t('RAGENT.AGENTS.ERROR'));
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
        <Button size="sm" :label="t('RAGENT.AGENTS.EDIT')" @click="edit(a)" />
        <Button
          size="sm"
          color="ruby"
          :label="t('RAGENT.AGENTS.ARCHIVE')"
          @click="archive(a)"
        />
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
      <label class="text-body-main text-n-slate-11">
        {{ t('RAGENT.AGENTS.TOOLS') }}
        <input v-model="toolsText" type="text" class="!mb-0 w-full" />
      </label>
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
