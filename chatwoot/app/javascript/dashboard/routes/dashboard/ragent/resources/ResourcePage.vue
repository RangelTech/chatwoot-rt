<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { RESOURCES } from './resourceConfig';

const { axios } = window;
const { t, te } = useI18n();
const route = useRoute();

const key = computed(() => route.meta.resource);
const config = computed(() => RESOURCES[key.value] || { columns: [], fields: [] });
const accountId = computed(() => route.params.accountId);
const base = computed(
  () => `/api/v1/accounts/${accountId.value}/rt_ai/resources/${key.value}`
);

const items = ref([]);
const raw = ref(null);
const loading = ref(true);
const forbidden = ref(false);
const creating = ref(false);
const form = ref({});
const busy = ref(false);

const cell = value => {
  if (value === null || value === undefined) return '';
  if (typeof value === 'boolean') return t(value ? 'RAGENT.RES.YES' : 'RAGENT.RES.NO');
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
};

// Resposta sem lista (Uso, Ambiente): vira linhas "rótulo: valor", nunca JSON cru para o cliente.
const humanize = key => {
  const upper = String(key).toUpperCase();
  if (te(`RAGENT.RES.KEYS.${upper}`)) return t(`RAGENT.RES.KEYS.${upper}`);
  const text = String(key).replace(/_/g, ' ');
  return text.charAt(0).toUpperCase() + text.slice(1);
};
const flatten = (value, prefix = '') => {
  if (value === null || value === undefined) return [{ label: prefix, value: '—' }];
  if (Array.isArray(value)) {
    if (!value.length) return [{ label: prefix, value: '—' }];
    return value.flatMap((v, i) =>
      typeof v === 'object' && v !== null
        ? flatten(v, `${prefix} ${i + 1}`.trim())
        : [{ label: prefix, value: cell(v) }]
    );
  }
  if (typeof value === 'object') {
    return Object.entries(value).flatMap(([k, v]) =>
      flatten(v, prefix ? `${prefix} · ${humanize(k)}` : humanize(k))
    );
  }
  return [{ label: prefix, value: cell(value) }];
};
const rawRows = computed(() => (raw.value ? flatten(raw.value) : []));

const load = async () => {
  loading.value = true;
  forbidden.value = false;
  try {
    const { data } = await axios.get(base.value);
    const list = Array.isArray(data)
      ? data
      : data.items || data.sessions || data.charges || data.records;
    if (Array.isArray(list)) {
      items.value = list;
      raw.value = null;
    } else {
      items.value = [];
      raw.value = data;
    }
  } catch (error) {
    forbidden.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(load);
watch(key, () => {
  creating.value = false;
  form.value = {};
  load();
});

const canManage = computed(() => !!config.value.manage);

const submit = async () => {
  busy.value = true;
  try {
    const body = {};
    config.value.fields.forEach(f => {
      const v = form.value[f.key];
      if (v === undefined || v === '') return;
      body[f.key] = f.json ? JSON.parse(v) : v;
    });
    await axios.post(base.value, body);
    form.value = {};
    creating.value = false;
    useAlert(t('RAGENT.RES.SAVED'));
    await load();
  } catch (error) {
    useAlert(t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = false;
  }
};

const remove = async item => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAGENT.RES.CONFIRM_DELETE'))) return;
  try {
    await axios.delete(`${base.value}/${item.id}`);
    await load();
  } catch (error) {
    useAlert(t('RAGENT.RES.ERROR'));
  }
};

const runAction = async name => {
  try {
    await axios.post(`${base.value}/actions/${name}`);
    useAlert(t('RAGENT.RES.SAVED'));
    await load();
  } catch (error) {
    useAlert(t('RAGENT.RES.ERROR'));
  }
};
</script>

<template>
  <div class="mx-auto flex h-full w-full max-w-5xl flex-col gap-4 overflow-y-auto p-6">
    <header class="flex items-center gap-3">
      <h1 class="text-heading-1 text-n-slate-12">
        {{ t(`RAGENT.RES.${config.title}.TITLE`) }}
      </h1>
      <div class="ms-auto flex gap-2">
        <Button
          v-for="a in config.actions || []"
          :key="a"
          size="sm"
          variant="faded"
          :label="t(`RAGENT.RES.ACTIONS.${a.toUpperCase()}`)"
          @click="runAction(a)"
        />
        <Button
          v-if="canManage && config.fields.length"
          :label="t('RAGENT.RES.NEW')"
          @click="creating = !creating"
        />
      </div>
    </header>
    <p class="text-body-main text-n-slate-11">
      {{ t(`RAGENT.RES.${config.title}.HELP`) }}
    </p>

    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="forbidden" class="text-n-slate-11">{{ t('RAGENT.CHAT.FORBIDDEN') }}</p>

    <section v-if="creating" class="flex flex-col gap-2 rounded-xl border border-n-weak p-4">
      <label v-for="f in config.fields" :key="f.key" class="text-body-main text-n-slate-11">
        {{ t(`RAGENT.RES.FIELDS.${f.label}`) }}
        <select v-if="f.options" v-model="form[f.key]" class="!mb-0 w-full">
          <option v-for="o in f.options" :key="o" :value="o">{{ o }}</option>
        </select>
        <textarea v-else-if="f.json" v-model="form[f.key]" rows="4" class="!mb-0 w-full font-mono" placeholder="{}" />
        <input
          v-else
          v-model="form[f.key]"
          :type="f.secret ? 'password' : 'text'"
          :autocomplete="f.secret ? 'new-password' : 'off'"
          class="!mb-0 w-full"
        />
      </label>
      <Button :label="t('RAGENT.RES.SAVE')" :disabled="busy" @click="submit" />
    </section>

    <div v-if="items.length" class="overflow-x-auto rounded-xl border border-n-weak">
      <table class="w-full text-start text-body-main">
        <thead>
          <tr class="border-b border-n-weak text-n-slate-11">
            <th v-for="c in config.columns" :key="c" class="px-4 py-2 text-start">
              {{ t(`RAGENT.RES.COLUMNS.${c.toUpperCase()}`) }}
            </th>
            <th v-if="canManage" />
          </tr>
        </thead>
        <tbody>
          <tr v-for="it in items" :key="it.id || JSON.stringify(it)" class="border-b border-n-weak last:border-0">
            <td v-for="c in config.columns" :key="c" class="px-4 py-2 text-n-slate-12">
              {{ cell(it[c]) }}
            </td>
            <td v-if="canManage && it.id" class="px-4 py-2 text-end">
              <Button size="sm" color="ruby" :label="t('RAGENT.RES.DELETE')" @click="remove(it)" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <dl
      v-else-if="raw"
      class="grid grid-cols-1 gap-x-6 gap-y-2 rounded-xl border border-n-weak p-4 text-body-main sm:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]"
    >
      <template v-for="(row, i) in rawRows" :key="i">
        <dt class="text-n-slate-11">{{ row.label }}</dt>
        <dd class="text-n-slate-12">{{ row.value }}</dd>
      </template>
    </dl>
    <p v-else-if="!loading && !forbidden" class="text-n-slate-11">{{ t('RAGENT.RES.EMPTY') }}</p>
  </div>
</template>
