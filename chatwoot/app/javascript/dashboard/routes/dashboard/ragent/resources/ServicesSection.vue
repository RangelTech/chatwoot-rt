<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatNumber } from './format';
import {
  REFRESH_MS,
  actionsFor,
  formatUptime,
  normalizeServices,
  originKey,
  portText,
  stateClass,
} from './services';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
});
const { axios } = window;
const { t } = useI18n();

const COLUMNS = ['NAME', 'STATE', 'UPTIME', 'CPU_RAM', 'PORT', 'URL', 'ORIGIN'];

const base = computed(
  () =>
    `/api/v1/accounts/${props.accountId}/rt_ai/resources/environment_services`
);

const data = ref(normalizeServices(null));
const loading = ref(true);
const failed = ref(false);
const forbidden = ref(false);
const canManage = ref(false);
const acting = ref('');
const logs = ref(null); // { service, log } | null
let timer = null;

const load = async ({ quiet = false } = {}) => {
  if (!quiet) loading.value = true;
  try {
    const response = await axios.get(base.value);
    data.value = normalizeServices(response.data);
    failed.value = false;
    forbidden.value = false;
  } catch (error) {
    const status = error?.response?.status;
    forbidden.value = status === 401 || status === 403;
    failed.value = !forbidden.value;
  } finally {
    loading.value = false;
  }
};

const loadPermissions = async () => {
  try {
    const { data: me } = await axios.get(
      `/api/v1/accounts/${props.accountId}/rt_ai/me`
    );
    canManage.value = (me?.scopes || []).includes('ai.environment.manage');
  } catch (error) {
    canManage.value = false;
  }
};

const act = async (service, action) => {
  const message = t('RAGENT.RES.ENV.SERVICES.CONFIRM_STOP', {
    name: service.nome,
  });
  // eslint-disable-next-line no-alert
  if (action === 'stop' && !window.confirm(message)) return;
  acting.value = service.nome;
  try {
    await axios.post(`${base.value}/${service.nome}/actions/${action}`);
    useAlert(t('RAGENT.RES.ENV.SERVICES.DONE'));
    await load({ quiet: true });
  } catch (error) {
    useAlert(t('RAGENT.RES.ENV.SERVICES.ACTION_ERROR'));
  } finally {
    acting.value = '';
  }
};

const showLogs = async service => {
  acting.value = service.nome;
  try {
    const response = await axios.get(`${base.value}/${service.nome}/logs`);
    logs.value = {
      service: service.nome,
      log: String(response.data?.log || ''),
    };
  } catch (error) {
    useAlert(t('RAGENT.RES.ENV.SERVICES.LOGS_ERROR'));
  } finally {
    acting.value = '';
  }
};

const numberText = (value, digits = 0, unit = '') =>
  value === null || value === undefined
    ? '—'
    : `${formatNumber(value, digits)}${unit}`;

const active = computed(() => data.value.ambiente === 'ativo');
const visible = computed(
  () =>
    !['desativado', 'sem_ambiente'].includes(data.value.ambiente) &&
    !forbidden.value
);
const notice = computed(() => {
  const key = { parado: 'STOPPED', suspenso: 'SUSPENDED' }[data.value.ambiente];
  return key ? t(`RAGENT.RES.ENV.SERVICES.${key}`) : '';
});

onMounted(() => {
  load();
  loadPermissions();
  timer = setInterval(() => {
    if (!acting.value) load({ quiet: true });
  }, REFRESH_MS);
});
onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <section v-if="visible" data-testid="services-section">
    <header class="mb-2 flex items-center gap-3">
      <h2 class="text-heading-3 text-n-slate-12">
        {{ t('RAGENT.RES.ENV.SERVICES.TITLE') }}
      </h2>
      <Button
        class="ms-auto"
        size="sm"
        variant="faded"
        data-testid="services-refresh"
        :label="t('RAGENT.RES.ENV.SERVICES.REFRESH')"
        @click="load()"
      />
    </header>

    <p v-if="failed" class="text-body-main text-n-amber-11" role="alert">
      {{ t('RAGENT.RES.ENV.SERVICES.LOAD_ERROR') }}
    </p>
    <p
      v-else-if="notice"
      class="rounded-xl border border-dashed border-n-weak px-4 py-4 text-body-main text-n-slate-11"
      data-testid="services-notice"
    >
      {{ notice }}
    </p>
    <template v-else-if="active">
      <p
        v-if="!data.servicos.length && !loading"
        class="rounded-xl border border-dashed border-n-weak px-4 py-4 text-body-main text-n-slate-11"
        data-testid="services-empty"
      >
        {{ t('RAGENT.RES.ENV.SERVICES.EMPTY') }}
      </p>
      <div v-else class="overflow-x-auto rounded-xl border border-n-weak">
        <table class="w-full text-start text-body-main">
          <thead>
            <tr class="border-b border-n-weak text-n-slate-11">
              <th v-for="c in COLUMNS" :key="c" class="px-4 py-2 text-start">
                {{ t(`RAGENT.RES.ENV.SERVICES.COLUMNS.${c}`) }}
              </th>
              <th v-if="canManage" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="s in data.servicos"
              :key="s.nome"
              class="border-b border-n-weak last:border-0"
              data-testid="service-row"
            >
              <td class="px-4 py-2 text-n-slate-12">{{ s.nome }}</td>
              <td class="px-4 py-2">
                <span
                  class="rounded-md px-2 py-0.5"
                  :class="stateClass(s.estado)"
                >
                  {{
                    t(
                      `RAGENT.RES.ENV.SERVICES.STATES.${String(s.estado).toUpperCase()}`
                    )
                  }}
                </span>
              </td>
              <td class="px-4 py-2 text-n-slate-12">
                {{ formatUptime(s.uptime_s) }}
              </td>
              <td class="px-4 py-2 text-n-slate-12">
                {{ numberText(s.cpu_pct, 1, '%') }} ·
                {{ numberText(s.mem_mb, 0, ' MB') }}
              </td>
              <td class="px-4 py-2 text-n-slate-12">{{ portText(s.portas) }}</td>
              <td class="px-4 py-2">
                <a
                  v-if="s.url_publica"
                  :href="s.url_publica"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-n-brand hover:underline"
                >
                  {{ s.url_publica }}
                </a>
                <span v-else>—</span>
              </td>
              <td class="px-4 py-2 text-n-slate-12">
                {{ t(`RAGENT.RES.ENV.SERVICES.ORIGINS.${originKey(s)}`) }}
              </td>
              <td v-if="canManage" class="px-4 py-2 text-end">
                <div class="flex flex-wrap justify-end gap-2">
                  <Button
                    v-for="a in actionsFor(s.estado)"
                    :key="a"
                    size="sm"
                    variant="faded"
                    :color="a === 'stop' ? 'ruby' : undefined"
                    :disabled="acting === s.nome"
                    :data-testid="`service-${a}`"
                    :label="
                      t(`RAGENT.RES.ENV.SERVICES.ACTIONS.${a.toUpperCase()}`)
                    "
                    @click="act(s, a)"
                  />
                  <Button
                    size="sm"
                    variant="faded"
                    :disabled="acting === s.nome"
                    data-testid="service-logs"
                    :label="t('RAGENT.RES.ENV.SERVICES.ACTIONS.LOGS')"
                    @click="showLogs(s)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        v-if="logs"
        class="mt-3 rounded-xl border border-n-weak p-3"
        data-testid="service-log-panel"
      >
        <div class="mb-2 flex items-center gap-2">
          <p class="text-body-main text-n-slate-11">
            {{ t('RAGENT.RES.ENV.SERVICES.LOGS_TITLE', { name: logs.service }) }}
          </p>
          <Button
            class="ms-auto"
            size="sm"
            variant="faded"
            :label="t('RAGENT.RES.ENV.SERVICES.CLOSE')"
            @click="logs = null"
          />
        </div>
        <pre
          class="max-h-80 overflow-auto whitespace-pre-wrap break-all font-mono text-body-main text-n-slate-12"
          >{{ logs.log || t('RAGENT.RES.ENV.SERVICES.NO_LOGS') }}</pre
        >
      </div>

      <div v-if="data.soltos.length" class="mt-4" data-testid="loose-section">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('RAGENT.RES.ENV.SERVICES.LOOSE_TITLE') }}
        </h3>
        <p class="mb-2 text-body-main text-n-slate-11">
          {{ t('RAGENT.RES.ENV.SERVICES.LOOSE_HELP') }}
        </p>
        <div class="overflow-x-auto rounded-xl border border-n-weak">
          <table class="w-full text-start text-body-main">
            <tbody>
              <tr
                v-for="p in data.soltos"
                :key="p.pid"
                class="border-b border-n-weak last:border-0"
                data-testid="loose-row"
              >
                <td class="px-4 py-2 text-n-slate-12">{{ p.comando }}</td>
                <td
                  class="max-w-xs truncate px-4 py-2 font-mono text-n-slate-11"
                  :title="p.argumentos"
                >
                  {{ p.argumentos }}
                </td>
                <td class="px-4 py-2 text-n-slate-12">
                  {{ formatUptime(p.uptime_s) }}
                </td>
                <td class="px-4 py-2 text-n-slate-12">
                  {{ numberText(p.cpu_pct, 1, '%') }} ·
                  {{ numberText(p.mem_mb, 0, ' MB') }}
                </td>
                <td class="px-4 py-2 text-n-slate-12">
                  {{ portText(p.portas) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div v-if="data.conteineres.length" class="mt-4">
        <h3 class="mb-2 text-heading-3 text-n-slate-12">
          {{ t('RAGENT.RES.ENV.SERVICES.CONTAINERS_TITLE') }}
        </h3>
        <ul class="rounded-xl border border-n-weak text-body-main">
          <li
            v-for="c in data.conteineres"
            :key="c.nome"
            class="flex gap-3 border-b border-n-weak px-4 py-2 last:border-0"
          >
            <span class="text-n-slate-12">{{ c.nome }}</span>
            <span class="text-n-slate-11">{{ c.imagem }}</span>
            <span class="ms-auto text-n-slate-11">{{ c.status }}</span>
          </li>
        </ul>
      </div>
    </template>
  </section>
</template>
