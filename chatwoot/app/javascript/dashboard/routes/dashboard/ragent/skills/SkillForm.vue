<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { composeSkill, parseSkill, slugify } from './skillText';

const props = defineProps({
  // 'company' (compartilhada com todos) ou 'mine' (só da pessoa)
  scope: { type: String, required: true },
  base: { type: String, required: true },
  // Skill existente (com id) para editar; sem ela, cria uma nova.
  skill: { type: Object, default: null },
});
const emit = defineEmits(['saved', 'cancel']);

const { t } = useI18n();
const { axios } = window;

const personal = computed(() => props.scope === 'mine');
const editing = computed(() => !!props.skill);
const name = ref('');
const description = ref('');
const body = ref('');
const extra = ref([]);
const busy = ref(false);
const loading = ref(editing.value);
const problems = ref([]);

const path = computed(() =>
  personal.value ? `${props.base}/skills` : `${props.base}/skills/company`
);

onMounted(async () => {
  if (!editing.value) return;
  try {
    const { data } = await axios.get(`${path.value}/${props.skill.id}`);
    const parsed = parseSkill(data.content);
    name.value = parsed.name || props.skill.name;
    description.value = parsed.description;
    body.value = parsed.body;
    extra.value = parsed.extra;
  } catch (error) {
    useAlert(t('RAGENT.SKILLS.ERROR'));
    emit('cancel');
  } finally {
    loading.value = false;
  }
});

const finalName = computed(() =>
  editing.value ? name.value : slugify(name.value, personal.value)
);
const valid = computed(
  () => finalName.value && description.value.trim() && body.value.trim()
);

const save = async () => {
  if (!valid.value) return;
  busy.value = true;
  problems.value = [];
  const content = composeSkill({
    name: finalName.value,
    description: description.value,
    body: body.value,
    extra: extra.value,
  });
  try {
    if (editing.value)
      await axios.put(`${path.value}/${props.skill.id}`, { content });
    else await axios.post(path.value, { content });
    useAlert(t('RAGENT.SKILLS.SAVED'));
    emit('saved');
  } catch (error) {
    const data = error.response?.data;
    problems.value = (data?.problems || []).map(p => p.message);
    if (!problems.value.length)
      problems.value = [data?.message || t('RAGENT.SKILLS.ERROR')];
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <form
    class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    @submit.prevent="save"
  >
    <h2 class="text-heading-2 text-n-slate-12">
      {{
        editing
          ? t('RAGENT.SKILLS.EDIT_TITLE')
          : t(personal ? 'RAGENT.SKILLS.NEW_MINE' : 'RAGENT.SKILLS.NEW_COMPANY')
      }}
    </h2>
    <p v-if="!personal" class="text-body-main text-n-slate-11">
      {{ t('RAGENT.SKILLS.COMPANY_HELP') }}
    </p>
    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <template v-else>
      <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.SKILLS.FIELD_NAME') }}
        <input
          v-model="name"
          type="text"
          class="!mb-0"
          maxlength="60"
          :disabled="editing"
          :placeholder="t('RAGENT.SKILLS.FIELD_NAME_HINT')"
        />
        <span v-if="!editing && finalName" class="text-xs text-n-slate-10">
          {{ t('RAGENT.SKILLS.NAME_PREVIEW', { name: finalName }) }}
        </span>
      </label>
      <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.SKILLS.FIELD_WHEN') }}
        <input
          v-model="description"
          type="text"
          class="!mb-0"
          maxlength="1024"
          :placeholder="t('RAGENT.SKILLS.FIELD_WHEN_HINT')"
        />
      </label>
      <label class="flex flex-col gap-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.SKILLS.FIELD_STEPS') }}
        <textarea
          v-model="body"
          rows="10"
          class="!mb-0 w-full font-mono text-sm"
          :placeholder="t('RAGENT.SKILLS.FIELD_STEPS_HINT')"
        />
      </label>
      <ul
        v-if="problems.length"
        class="list-disc pl-5 text-body-main text-n-ruby-11"
      >
        <li v-for="p in problems" :key="p">{{ p }}</li>
      </ul>
      <div class="flex gap-2">
        <Button
          type="submit"
          size="sm"
          :label="t('RAGENT.RES.SAVE')"
          :disabled="busy || !valid"
        />
        <Button
          size="sm"
          variant="faded"
          type="button"
          :label="t('RAGENT.SKILLS.CANCEL')"
          @click="emit('cancel')"
        />
      </div>
    </template>
  </form>
</template>
