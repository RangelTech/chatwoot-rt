<script setup>
import AiSettingsTabs from '../AiSettingsTabs.vue';
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CREDENTIAL_TYPES,
  DB_PORTS,
  buildPayload,
  initialForm,
  missingFields,
  typeOf,
  visibleFields,
} from './credentialTypes';

const { axios } = window;
const { t, te } = useI18n();
const route = useRoute();
const base = computed(
  () => `/api/v1/accounts/${route.params.accountId}/rt_ai/credentials`
);

const items = ref([]);
const loading = ref(true);
const forbidden = ref(false);
const busy = ref(false);

// Painel de criação/substituição: `editing` é o item sendo substituído (null = nova credencial).
const open = ref(false);
const typeKey = ref('secret');
const editing = ref(null);
const form = ref({});
const fileName = ref('');
const waitingOauth = ref('');
let pollTimer = null;

const type = computed(() => typeOf(typeKey.value));
const fields = computed(() => visibleFields(type.value, form.value));
const isOauth = computed(() => !!type.value?.oauth);

const load = async () => {
  try {
    const { data } = await axios.get(base.value);
    items.value = data.items || [];
    forbidden.value = false;
  } catch (error) {
    forbidden.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(load);

const stopPolling = () => {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
  waitingOauth.value = '';
};
onBeforeUnmount(stopPolling);

const resetForm = () => {
  form.value = initialForm(type.value, editing.value);
  fileName.value = '';
};

const startCreate = () => {
  editing.value = null;
  typeKey.value = 'secret';
  resetForm();
  open.value = true;
};

watch(typeKey, () => {
  if (!editing.value) resetForm();
});

const onDbKind = () => {
  form.value.port = DB_PORTS[form.value.db_kind] || '';
};

const reconnect = item => {
  editing.value = null;
  typeKey.value = item.type;
  resetForm();
  open.value = true;
};

const startReplace = item => {
  editing.value = item;
  typeKey.value = item.type;
  resetForm();
  open.value = true;
};

const close = () => {
  open.value = false;
  editing.value = null;
  form.value = {};
  fileName.value = '';
};

const label = key => t(`RAGENT.CRED.FIELDS.${key.toUpperCase()}`);

const onJsonFile = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  try {
    const content = await file.text();
    JSON.parse(content);
    form.value.value = content;
    fileName.value = file.name;
  } catch (error) {
    useAlert(t('RAGENT.CRED.INVALID_JSON'));
  }
  // eslint-disable-next-line no-param-reassign
  event.target.value = '';
};

const submit = async () => {
  const replace = !!editing.value;
  if (missingFields(type.value, form.value, { replace }).length) {
    useAlert(t('RAGENT.CRED.REQUIRED'));
    return;
  }
  busy.value = true;
  try {
    const body = buildPayload(type.value, form.value, { replace });
    if (replace) {
      await axios.put(
        `${base.value}/${editing.value.type}/${editing.value.id}`,
        body
      );
    } else {
      await axios.post(base.value, body);
    }
    useAlert(t('RAGENT.CRED.SAVED'));
    close();
    await load();
  } catch (error) {
    useAlert(error?.response?.data?.message || t('RAGENT.RES.ERROR'));
  } finally {
    busy.value = false;
  }
};

// OAuth: abre a tela de autorização do provedor; o motor fecha a conexão quando ele volta,
// e esta tela só confere a lista até a conta aparecer.
const connect = async providerKey => {
  busy.value = true;
  try {
    const before = items.value.filter(i => i.type === providerKey).length;
    const { data } = await axios.post(`${base.value}/oauth/${providerKey}`, {
      label: form.value.name || undefined,
    });
    window.open(data.auth_url, '_blank');
    close();
    waitingOauth.value = providerKey;
    const deadline = Date.now() + 3 * 60 * 1000;
    pollTimer = setInterval(async () => {
      await load();
      const now = items.value.filter(i => i.type === providerKey).length;
      if (now > before) {
        stopPolling();
        useAlert(t('RAGENT.CRED.CONNECTED'));
      } else if (Date.now() > deadline) {
        stopPolling();
      }
    }, 3000);
  } catch (error) {
    useAlert(error?.response?.data?.message || t('RAGENT.CRED.OAUTH_ERROR'));
  } finally {
    busy.value = false;
  }
};

const testing = ref('');
const testResult = ref({});
const runTest = async item => {
  testing.value = item.id;
  try {
    const { data } = await axios.post(`${base.value}/${item.type}/${item.id}/test`);
    testResult.value = { ...testResult.value, [item.id]: data };
  } catch (error) {
    testResult.value = {
      ...testResult.value,
      [item.id]: { ok: false, detail: t('RAGENT.CRED.TEST_FAILED') },
    };
  } finally {
    testing.value = '';
  }
};

const remove = async item => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAGENT.CRED.CONFIRM_REMOVE', { name: item.name })))
    return;
  try {
    await axios.delete(`${base.value}/${item.type}/${item.id}`);
    await load();
  } catch (error) {
    useAlert(t('RAGENT.RES.ERROR'));
  }
};

const dbLabel = kind => {
  const key = `RAGENT.CRED.DB_KINDS.${String(kind).toUpperCase()}`;
  return te(key) ? t(key) : String(kind || '');
};

// Resumo sem valores: só o que não é segredo (servidor, usuário, final do token).
const details = item => {
  const i = item.info || {};
  switch (item.type) {
    case 'secret':
      return i.hint ? `••••${i.hint}` : t('RAGENT.CRED.STORED');
    case 'ssh':
      return `${i.user}@${i.host}:${i.port || 22}`;
    case 'gcp':
    case 'aws':
    case 'azure':
      return t('RAGENT.CRED.STORED_JSON');
    case 'database': {
      if (i.db_kind === 'sqlite')
        return `${dbLabel(i.db_kind)} · ${i.path || ''}`;
      const port = i.port ? `:${i.port}` : '';
      return `${dbLabel(i.db_kind)} · ${i.host || ''}${port}${i.database ? `/${i.database}` : ''}`;
    }
    case 'email':
      return i.email_address;
    case 'payment':
      return t(i.sandbox ? 'RAGENT.CRED.SANDBOX' : 'RAGENT.CRED.PRODUCTION');
    default:
      return i.email_address || '';
  }
};

const when = value => (value ? new Date(value).toLocaleString() : '');
const isOauthItem = item => ['google', 'microsoft'].includes(item.type);
</script>

<template>
  <div
    class="mx-auto flex h-full w-full max-w-6xl flex-col gap-4 overflow-y-auto p-6"
  >
    <AiSettingsTabs />
    <p class="rounded-xl bg-n-alpha-2 p-3 text-body-main text-n-slate-11">
      {{ t('RAGENT.CRED.WORKSPACE_INTRO') }}
    </p>
    <header class="flex items-center gap-3">
      <h1 class="text-heading-1 text-n-slate-12">
        {{ t('RAGENT.CRED.TITLE') }}
      </h1>
      <div class="ms-auto">
        <Button
          :label="t('RAGENT.CRED.NEW')"
          @click="open ? close() : startCreate()"
        />
      </div>
    </header>
    <p class="text-body-main text-n-slate-11">{{ t('RAGENT.CRED.HELP') }}</p>

    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="forbidden" class="text-n-slate-11">
      {{ t('RAGENT.CHAT.FORBIDDEN') }}
    </p>
    <p
      v-if="waitingOauth"
      class="rounded-xl border border-n-weak p-3 text-n-slate-11"
    >
      {{ t('RAGENT.CRED.WAITING_OAUTH') }}
    </p>

    <section
      v-if="open"
      class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    >
      <h2 class="text-heading-2 text-n-slate-12">
        {{
          editing
            ? t('RAGENT.CRED.REPLACE_TITLE', { name: editing.name })
            : t('RAGENT.CRED.NEW')
        }}
      </h2>

      <label v-if="!editing" class="text-body-main text-n-slate-11">
        {{ t('RAGENT.CRED.TYPE') }}
        <select v-model="typeKey" class="!mb-0 w-full">
          <option v-for="ty in CREDENTIAL_TYPES" :key="ty.key" :value="ty.key">
            {{ t(`RAGENT.CRED.TYPES.${ty.key.toUpperCase()}`) }}
          </option>
        </select>
      </label>
      <p class="text-body-main text-n-slate-11">
        {{ t(`RAGENT.CRED.TYPE_HELP.${typeKey.toUpperCase()}`) }}
      </p>
      <p v-if="editing && !isOauth" class="text-body-main text-n-slate-11">
        {{ t('RAGENT.CRED.KEEP_BLANK') }}
      </p>

      <template v-if="isOauth">
        <label class="text-body-main text-n-slate-11">
          {{ t('RAGENT.CRED.FIELDS.ACCOUNT_NAME') }}
          <input
            v-model="form.name"
            type="text"
            class="!mb-0 w-full"
            autocomplete="off"
          />
        </label>
        <div>
          <Button
            :label="t('RAGENT.CRED.CONNECT')"
            :disabled="busy"
            @click="connect(typeKey)"
          />
        </div>
      </template>

      <template v-else>
        <template v-for="f in fields" :key="f.key">
          <label
            v-if="!(editing && (f.key === 'name' || f.key === 'db_kind'))"
            class="text-body-main text-n-slate-11"
            :class="{ 'flex items-center gap-2': f.kind === 'checkbox' }"
          >
            <input
              v-if="f.kind === 'checkbox'"
              v-model="form[f.key]"
              type="checkbox"
              class="!mb-0"
            />
            <span>
              {{ label(f.key) }}
              <span v-if="f.optional" class="text-n-slate-10">
                {{ t('RAGENT.CRED.OPTIONAL') }}
              </span>
            </span>
            <select
              v-if="f.kind === 'select'"
              v-model="form[f.key]"
              class="!mb-0 w-full"
              @change="onDbKind"
            >
              <option v-for="o in f.options" :key="o" :value="o">
                {{ dbLabel(o) }}
              </option>
            </select>
            <textarea
              v-else-if="f.kind === 'textarea'"
              v-model="form[f.key]"
              rows="6"
              class="!mb-0 w-full font-mono"
              :placeholder="f.placeholder"
              autocomplete="off"
              spellcheck="false"
            />
            <div v-else-if="f.kind === 'json-file'" class="flex flex-col gap-2">
              <input
                type="file"
                accept=".json,application/json"
                @change="onJsonFile"
              />
              <span v-if="fileName" class="text-n-slate-12">{{
                fileName
              }}</span>
              <textarea
                v-model="form[f.key]"
                rows="4"
                class="!mb-0 w-full font-mono"
                :placeholder="t('RAGENT.CRED.PASTE_JSON')"
                autocomplete="off"
                spellcheck="false"
              />
            </div>
            <input
              v-else-if="f.kind !== 'checkbox'"
              v-model="form[f.key]"
              :type="f.kind === 'number' ? 'number' : f.kind"
              :placeholder="f.placeholder"
              :autocomplete="f.secret ? 'new-password' : 'off'"
              class="!mb-0 w-full"
            />
          </label>
        </template>
        <div class="flex gap-2">
          <Button
            :label="t('RAGENT.CRED.SAVE')"
            :disabled="busy"
            @click="submit"
          />
          <Button
            variant="faded"
            :label="t('RAGENT.CRED.CANCEL')"
            @click="close"
          />
        </div>
      </template>
    </section>

    <div
      v-if="items.length"
      class="overflow-x-auto rounded-xl border border-n-weak"
    >
      <table class="w-full text-start text-body-main">
        <thead>
          <tr class="border-b border-n-weak text-n-slate-11">
            <th class="px-4 py-2 text-start">
              {{ t('RAGENT.CRED.COLUMNS.NAME') }}
            </th>
            <th class="px-4 py-2 text-start">
              {{ t('RAGENT.CRED.COLUMNS.TYPE') }}
            </th>
            <th class="px-4 py-2 text-start">
              {{ t('RAGENT.CRED.COLUMNS.DETAILS') }}
            </th>
            <th class="px-4 py-2 text-start">
              {{ t('RAGENT.CRED.COLUMNS.VARS') }}
            </th>
            <th class="px-4 py-2 text-start">
              {{ t('RAGENT.CRED.COLUMNS.UPDATED') }}
            </th>
            <th />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="it in items"
            :key="`${it.type}-${it.id}`"
            class="border-b border-n-weak last:border-0"
          >
            <td class="px-4 py-2 text-n-slate-12">{{ it.name }}</td>
            <td class="px-4 py-2 text-n-slate-12">
              {{ t(`RAGENT.CRED.TYPES.${it.type.toUpperCase()}`) }}
            </td>
            <td class="break-all px-4 py-2 text-n-slate-12">{{ details(it) }}</td>
            <td class="px-4 py-2">
              <code
                v-for="v in it.env_vars"
                :key="v"
                class="me-1 inline-block rounded bg-n-alpha-2 px-1 text-xs text-n-slate-12"
              >
                {{ v }}
              </code>
            </td>
            <td class="px-4 py-2 text-n-slate-11">
              {{ when(it.updated_at || it.created_at) }}
            </td>
            <td class="whitespace-nowrap px-4 py-2 text-end">
              <Button
                size="sm"
                variant="faded"
                :label="
                  t(
                    isOauthItem(it)
                      ? 'RAGENT.CRED.RECONNECT'
                      : 'RAGENT.CRED.REPLACE'
                  )
                "
                @click="isOauthItem(it) ? reconnect(it) : startReplace(it)"
              />
              <Button
                v-if="['secret', 'ssh', 'gcp', 'aws', 'azure'].includes(it.type)"
                size="sm"
                variant="faded"
                :disabled="testing === it.id"
                :label="t('RAGENT.CRED.TEST')"
                @click="runTest(it)"
              />
              <p
                v-if="testResult[it.id]"
                class="mt-1 text-sm"
                :class="testResult[it.id].ok ? 'text-n-teal-11' : 'text-n-ruby-11'"
                role="status"
              >
                {{ testResult[it.id].detail }}
              </p>
              <Button
                size="sm"
                color="ruby"
                :label="t('RAGENT.CRED.REMOVE')"
                @click="remove(it)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-else-if="!loading && !forbidden" class="text-n-slate-11">
      {{ t('RAGENT.CRED.EMPTY') }}
    </p>
    <p v-if="items.length" class="text-body-main text-n-slate-11">
      {{ t('RAGENT.CRED.VARS_HELP') }}
    </p>
  </div>
</template>
