<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { RESOURCES } from './resourceConfig';
import UsagePanel from './UsagePanel.vue';
import EnvironmentPanel from './EnvironmentPanel.vue';
import ProviderCostPanel from './ProviderCostPanel.vue';
import ProviderOauth from './ProviderOauth.vue';
import ComboEditor from './ComboEditor.vue';
import { formatBytes, formatDate, formatNumber, isDateKey } from './format';

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
const failed = ref(false);
const creating = ref(false);
const form = ref({});
const busy = ref(false);
// Chave de integração: o servidor a devolve uma única vez, na criação.
const newKey = ref('');
const providerModels = ref([]);
const providerQuota = ref(null);
const showOauth = ref(false);
const editingCombo = ref(null);
const comboSuggestions = ref([]);

// Valor de célula legível: data em pt-BR, número com separador, situação com rótulo; objeto nunca vira JSON.
const cell = (value, column = '') => {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'boolean') return t(value ? 'RAGENT.RES.YES' : 'RAGENT.RES.NO');
  // Combos exibem uma lista de modelos. Objetos continuam ocultos para não
  // despejar estruturas internas cruas na tela.
  if (Array.isArray(value)) return value.map(item => String(item)).join(', ') || '—';
  if (typeof value === 'object') return '—';
  if (isDateKey(column)) return formatDate(value);
  if (column === 'size_bytes') return formatBytes(value);
  if (column === 'status') {
    const k = `RAGENT.RES.STATUS.${String(value).toUpperCase()}`;
    return te(k) ? t(k) : String(value);
  }
  if (typeof value === 'number') return formatNumber(value, Number.isInteger(value) ? 0 : 2);
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(value)) return formatDate(value);
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
  failed.value = false;
  try {
    const { data } = await axios.get(base.value);
    const list = Array.isArray(data)
      ? data
      : data.items || data.sessions || data.charges || data.records || data.requests;
    if (Array.isArray(list)) {
      items.value = list;
      raw.value = null;
    } else {
      items.value = [];
      raw.value = data;
    }
  } catch (error) {
    // Só 401/403 é "sem permissão"; qualquer outra falha é indisponibilidade, com nova tentativa.
    const status = error?.response?.status;
    forbidden.value = status === 401 || status === 403;
    failed.value = !forbidden.value;
  } finally {
    loading.value = false;
  }
};

onMounted(load);
watch(key, () => {
  creating.value = false;
  showOauth.value = false;
  editingCombo.value = null;
  providerModels.value = [];
  providerQuota.value = null;
  newKey.value = '';
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
    const { data } = await axios.post(base.value, body);
    newKey.value = data?.api_key || '';
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

// Sugestões do editor de combos: só provedores e combos do tenant da sessão.
const openComboEditor = async combo => {
  editingCombo.value = combo || {};
  creating.value = false;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/rt_ai/resources/providers`
    );
    comboSuggestions.value = (Array.isArray(data) ? data : [])
      .filter(c => c.provider && (c.defaultModel || c.model))
      .map(c => `${c.provider}/${c.defaultModel || c.model}`);
  } catch (error) {
    comboSuggestions.value = [];
  }
  comboSuggestions.value = [
    ...comboSuggestions.value,
    ...items.value.filter(c => c.id !== combo?.id).map(c => c.name),
  ];
};

const saveCombo = async payload => {
  busy.value = true;
  try {
    if (editingCombo.value?.id) {
      await axios.put(`${base.value}/${editingCombo.value.id}`, payload);
    } else {
      await axios.post(base.value, payload);
    }
    editingCombo.value = null;
    useAlert(t('RAGENT.RES.SAVED'));
    await load();
  } catch (error) {
    useAlert(error?.response?.data?.message || t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = false;
  }
};

const loadQuota = async item => {
  busy.value = true;
  providerQuota.value = null;
  try {
    const { data } = await axios.get(`${base.value}/${item.id}/quota`);
    providerQuota.value = { name: item.name || item.provider, data };
  } catch (error) {
    providerQuota.value = { name: item.name || item.provider, data: null };
    useAlert(error?.response?.data?.message || t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = false;
  }
};

const quotaRows = computed(() =>
  providerQuota.value?.data ? flatten(providerQuota.value.data) : []
);

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

const runItemAction = async (item, name) => {
  busy.value = true;
  try {
    const { data } = await axios.post(`${base.value}/${item.id}/actions/${name}`);
    if (name === 'test' && data.valid === false) {
      useAlert(data.error || t('RAGENT.RES.TEST_FAILED'));
    } else {
      useAlert(t('RAGENT.RES.TEST_OK'));
    }
    await load();
  } catch (error) {
    useAlert(error?.response?.data?.message || t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = false;
  }
};

// O estado ativo e alterado pelo BFF tenant-scoped; nunca enviamos tenant, URL
// do gateway ou qualquer credencial a partir do navegador.
const toggleActive = async item => {
  busy.value = true;
  try {
    const current = item.is_active ?? item.isActive ?? true;
    await axios.put(`${base.value}/${item.id}`, { is_active: !current });
    useAlert(t('RAGENT.RES.SAVED'));
    await load();
  } catch (error) {
    useAlert(error?.response?.data?.message || t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = false;
  }
};

const loadProviderModels = async item => {
  busy.value = true;
  try {
    const { data } = await axios.get(`${base.value}/${item.id}/models`);
    providerModels.value = Array.isArray(data?.models) ? data.models : [];
  } catch (error) {
    providerModels.value = [];
    useAlert(error?.response?.data?.message || t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = false;
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
          v-if="canManage && key === 'providers'"
          variant="faded"
          :label="t('RAGENT.RES.GW.OAUTH.BUTTON')"
          @click="showOauth = !showOauth"
        />
        <Button
          v-if="canManage && key === 'combos'"
          :label="t('RAGENT.RES.NEW')"
          @click="openComboEditor(null)"
        />
        <Button
          v-else-if="canManage && config.fields.length"
          :label="t('RAGENT.RES.NEW')"
          @click="creating = !creating"
        />
      </div>
    </header>
    <p class="text-body-main text-n-slate-11">
      {{ t(`RAGENT.RES.${config.title}.HELP`) }}
    </p>

    <p v-if="newKey" class="rounded-xl border border-n-weak p-3 text-n-slate-12">
      {{ t('RAGENT.RES.NEW_KEY') }}
      <code class="mt-1 block break-all font-mono">{{ newKey }}</code>
    </p>

    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="forbidden" class="text-n-slate-11">{{ t('RAGENT.CHAT.FORBIDDEN') }}</p>
    <div
      v-else-if="failed"
      class="flex flex-wrap items-center gap-3 rounded-xl border border-n-weak p-4"
      role="alert"
      data-testid="resource-error"
    >
      <p class="min-w-0 flex-1 text-body-main text-n-slate-11">
        {{ t('RAGENT.RES.LOAD_ERROR') }}
      </p>
      <Button size="sm" variant="faded" :label="t('RAGENT.RES.RETRY')" @click="load" />
    </div>

    <ProviderOauth
      v-if="showOauth && key === 'providers'"
      :base="`/api/v1/accounts/${accountId}/rt_ai`"
      @done="load"
    />
    <ComboEditor
      v-if="editingCombo && key === 'combos'"
      :key="editingCombo.id || 'new'"
      :initial="editingCombo.id ? editingCombo : null"
      :suggestions="comboSuggestions"
      :busy="busy"
      @save="saveCombo"
      @cancel="editingCombo = null"
    />
    <section v-if="creating && key !== 'combos'" class="flex flex-col gap-2 rounded-xl border border-n-weak p-4">
      <label v-for="f in config.fields" :key="f.key" class="text-body-main text-n-slate-11">
        {{ t(`RAGENT.RES.FIELDS.${f.label}`) }}
        <select v-if="f.options" v-model="form[f.key]" class="!mb-0 w-full">
          <option v-for="o in f.options" :key="o" :value="o">{{ o }}</option>
        </select>
        <textarea v-else-if="f.json" v-model="form[f.key]" rows="4" class="!mb-0 w-full font-mono" :placeholder="f.placeholder || '{}'" />
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
              {{ cell(it[c], c) }}
            </td>
            <td v-if="canManage && it.id" class="px-4 py-2 text-end">
              <Button
                v-for="a in config.itemActions || []"
                :key="a"
                size="sm"
                variant="faded"
                :disabled="busy"
                :label="t(`RAGENT.RES.ACTIONS.${a.toUpperCase()}`)"
                @click="runItemAction(it, a)"
              />
              <Button
                v-for="a in config.itemReads || []"
                :key="a"
                size="sm"
                variant="faded"
                :disabled="busy"
                :label="t(`RAGENT.RES.ACTIONS.${a.toUpperCase()}`)"
                @click="loadProviderModels(it)"
              />
              <Button
                v-if="key === 'providers'"
                size="sm"
                variant="faded"
                :disabled="busy"
                :label="t('RAGENT.RES.GW.QUOTA.BUTTON')"
                @click="loadQuota(it)"
              />
              <Button
                v-if="key === 'combos'"
                size="sm"
                variant="faded"
                :disabled="busy"
                :label="t('RAGENT.RES.GW.COMBO.EDIT')"
                @click="openComboEditor(it)"
              />
              <Button
                v-if="key === 'providers'"
                size="sm"
                variant="faded"
                :disabled="busy"
                :label="t((it.is_active ?? it.isActive ?? true) ? 'RAGENT.RES.ACTIONS.DEACTIVATE' : 'RAGENT.RES.ACTIONS.ACTIVATE')"
                @click="toggleActive(it)"
              />
              <Button size="sm" color="ruby" :label="t('RAGENT.RES.DELETE')" @click="remove(it)" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <section v-if="providerModels.length" class="rounded-xl border border-n-weak p-4">
      <h2 class="mb-2 text-heading-4 text-n-slate-12">{{ t('RAGENT.RES.AVAILABLE_MODELS') }}</h2>
      <ul class="grid gap-1 text-body-main text-n-slate-11 sm:grid-cols-2">
        <li v-for="model in providerModels" :key="model.id || model.name">{{ model.name || model.id }}</li>
      </ul>
    </section>
    <section v-if="providerQuota" class="rounded-xl border border-n-weak p-4" data-testid="provider-quota">
      <h2 class="mb-2 text-heading-4 text-n-slate-12">
        {{ t('RAGENT.RES.GW.QUOTA.TITLE', { name: providerQuota.name }) }}
      </h2>
      <p v-if="!quotaRows.length || providerQuota.data?.message" class="text-body-main text-n-slate-11">
        {{ t('RAGENT.RES.GW.QUOTA.UNAVAILABLE') }}
      </p>
      <dl v-else class="grid grid-cols-1 gap-x-6 gap-y-2 text-body-main sm:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
        <template v-for="(row, i) in quotaRows" :key="i">
          <dt class="text-n-slate-11">{{ row.label }}</dt>
          <dd class="text-n-slate-12">{{ row.value }}</dd>
        </template>
      </dl>
    </section>
    <ProviderCostPanel v-if="raw && key === 'usage' && raw.byProvider" :data="raw" />
    <UsagePanel v-else-if="raw && key === 'usage'" :data="raw" />
    <EnvironmentPanel v-else-if="raw && key === 'environment'" :data="raw" />
    <dl
      v-else-if="raw"
      class="grid grid-cols-1 gap-x-6 gap-y-2 rounded-xl border border-n-weak p-4 text-body-main sm:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]"
    >
      <template v-for="(row, i) in rawRows" :key="i">
        <dt class="text-n-slate-11">{{ row.label }}</dt>
        <dd class="text-n-slate-12">{{ row.value }}</dd>
      </template>
    </dl>
    <p v-else-if="!loading && !forbidden && !failed" class="text-n-slate-11">{{ t('RAGENT.RES.EMPTY') }}</p>
  </div>
</template>
