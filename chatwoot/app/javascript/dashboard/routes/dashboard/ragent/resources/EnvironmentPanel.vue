<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { formatDate, formatNumber, percent } from './format';
import ServicesSection from './ServicesSection.vue';

const props = defineProps({ data: { type: Object, required: true } });
const { t, te } = useI18n();
const route = useRoute();

// Rótulo em português para estados/situações; valor desconhecido aparece como veio, sem quebrar.
const label = (group, value) => {
  const key = `RAGENT.RES.${group}.${String(value).toUpperCase()}`;
  return te(key) ? t(key) : String(value ?? '—');
};

const usage = computed(() => props.data.usage || {});
const apps = computed(() =>
  Array.isArray(props.data.apps) ? props.data.apps : []
);
const domains = computed(() =>
  Array.isArray(props.data.domains) ? props.data.domains : []
);
const disabled = computed(
  () => props.data.enabled === false || props.data.state === 'disabled'
);
const stateClass = computed(
  () =>
    ({
      running: 'bg-n-teal-3 text-n-teal-11',
      degraded: 'bg-n-amber-3 text-n-amber-11',
      suspended: 'bg-n-ruby-3 text-n-ruby-11',
    })[props.data.state] || 'bg-n-alpha-2 text-n-slate-11'
);

const meters = computed(() => {
  const u = usage.value;
  return [
    { key: 'CPU', value: u.cpu_pct, limit: 100, unit: '%', digits: 0 },
    { key: 'RAM', value: u.ram_mb, limit: u.ram_limit_mb, unit: 'MB', digits: 0 },
    { key: 'DISK', value: u.disk_gb, limit: u.disk_limit_gb, unit: 'GB', digits: 1 },
    { key: 'EGRESS', value: u.egress_gb, limit: null, unit: 'GB', digits: 1 },
  ];
});
const meterText = m =>
  m.limit && m.unit !== '%'
    ? t('RAGENT.RES.ENV.OF', {
        used: formatNumber(m.value, m.digits),
        limit: formatNumber(m.limit, m.digits),
        unit: m.unit,
      })
    : `${formatNumber(m.value, m.digits)} ${m.unit}`;
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="environment-panel">
    <p
      v-if="disabled"
      class="rounded-xl border border-dashed border-n-weak px-4 py-6 text-body-main text-n-slate-11"
    >
      {{ t('RAGENT.RES.ENV.DISABLED') }}
    </p>
    <template v-else>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <div class="rounded-xl border border-n-weak p-4">
          <p class="text-body-main text-n-slate-11">
            {{ t('RAGENT.RES.ENV.STATE') }}
          </p>
          <span
            class="mt-1 inline-block rounded-md px-2 py-0.5 text-body-main"
            :class="stateClass"
          >
            {{ label('STATE', data.state) }}
          </span>
        </div>
        <div class="rounded-xl border border-n-weak p-4">
          <p class="text-body-main text-n-slate-11">
            {{ t('RAGENT.RES.ENV.PLAN') }}
          </p>
          <p class="mt-1 text-heading-3 text-n-slate-12">
            {{ data.plan || '—' }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak p-4">
          <p class="text-body-main text-n-slate-11">
            {{ t('RAGENT.RES.ENV.LAST_BACKUP') }}
          </p>
          <p class="mt-1 text-heading-3 text-n-slate-12">
            {{
              data.last_backup_at
                ? formatDate(data.last_backup_at)
                : t('RAGENT.RES.ENV.NO_BACKUP')
            }}
          </p>
        </div>
      </div>
      <p v-if="data.state === 'degraded'" class="text-body-main text-n-amber-11">
        {{ t('RAGENT.RES.ENV.DEGRADED') }}
      </p>

      <section>
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          {{ t('RAGENT.RES.ENV.QUOTA') }}
        </h2>
        <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <div
            v-for="m in meters"
            :key="m.key"
            class="rounded-xl border border-n-weak p-4"
          >
            <p class="text-body-main text-n-slate-11">
              {{ t(`RAGENT.RES.ENV.${m.key}`) }}
            </p>
            <p class="mt-1 text-heading-3 text-n-slate-12">
              {{ meterText(m) }}
            </p>
            <div
              v-if="percent(m.value, m.limit) !== null"
              class="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-n-alpha-2"
            >
              <div
                class="h-full bg-n-brand"
                :style="{ width: `${percent(m.value, m.limit)}%` }"
              />
            </div>
          </div>
        </div>
      </section>

      <section>
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          {{ t('RAGENT.RES.ENV.APPS') }}
        </h2>
        <p
          v-if="!apps.length"
          class="rounded-xl border border-dashed border-n-weak px-4 py-4 text-body-main text-n-slate-11"
        >
          {{ t('RAGENT.RES.ENV.NO_APPS') }}
        </p>
        <div v-else class="overflow-x-auto rounded-xl border border-n-weak">
          <table class="w-full text-start text-body-main">
            <thead>
              <tr class="border-b border-n-weak text-n-slate-11">
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.COLUMNS.NAME') }}
                </th>
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.ENV.ADDRESS') }}
                </th>
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.COLUMNS.STATUS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="a in apps"
                :key="a.id || a.name"
                class="border-b border-n-weak last:border-0"
              >
                <td class="px-4 py-2 text-n-slate-12">{{ a.name }}</td>
                <td class="px-4 py-2">
                  <a
                    v-if="a.url"
                    :href="a.url"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-n-brand hover:underline"
                  >
                    {{ a.url }}
                  </a>
                  <span v-else>—</span>
                </td>
                <td class="px-4 py-2 text-n-slate-12">
                  {{ label('STATUS', a.status) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <ServicesSection :account-id="route.params.accountId" />

      <section>
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          {{ t('RAGENT.RES.ENV.DOMAINS') }}
        </h2>
        <p
          v-if="!domains.length"
          class="rounded-xl border border-dashed border-n-weak px-4 py-4 text-body-main text-n-slate-11"
        >
          {{ t('RAGENT.RES.ENV.NO_DOMAINS') }}
        </p>
        <div v-else class="overflow-x-auto rounded-xl border border-n-weak">
          <table class="w-full text-start text-body-main">
            <thead>
              <tr class="border-b border-n-weak text-n-slate-11">
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.ENV.DOMAIN') }}
                </th>
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.COLUMNS.STATUS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="d in domains"
                :key="d.id || d.host"
                class="border-b border-n-weak last:border-0"
              >
                <td class="px-4 py-2 text-n-slate-12">{{ d.host }}</td>
                <td class="px-4 py-2 text-n-slate-12">
                  {{ label('STATUS', d.status) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>
