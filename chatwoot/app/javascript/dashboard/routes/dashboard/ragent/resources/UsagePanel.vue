<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  formatBRL,
  formatDate,
  formatDuration,
  formatNumber,
  USD_BRL_ESTIMATE,
} from './format';

const props = defineProps({ data: { type: Object, required: true } });
const { t } = useI18n();

const totals = computed(() => props.data.totals || {});
const byModel = computed(() =>
  Array.isArray(props.data.by_model) ? props.data.by_model : []
);
const byDay = computed(() =>
  Array.isArray(props.data.by_day) ? props.data.by_day : []
);
const isEmpty = computed(() => !Number(totals.value.calls || 0));
const rate = computed(() => formatNumber(USD_BRL_ESTIMATE, 2));

const cards = computed(() => [
  { key: 'CALLS', value: formatNumber(totals.value.calls) },
  { key: 'PROMPT_TOKENS', value: formatNumber(totals.value.prompt_tokens) },
  {
    key: 'COMPLETION_TOKENS',
    value: formatNumber(totals.value.completion_tokens),
  },
  { key: 'AVG_LATENCY', value: formatDuration(totals.value.avg_latency_ms) },
  { key: 'COST', value: formatBRL(totals.value.cost_usd), estimated: true },
]);
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="usage-panel">
    <p
      v-if="isEmpty"
      class="rounded-xl border border-dashed border-n-weak px-4 py-6 text-body-main text-n-slate-11"
    >
      {{ t('RAGENT.RES.USAGE_PANEL.EMPTY') }}
    </p>
    <template v-else>
      <div class="grid grid-cols-2 gap-3 md:grid-cols-5">
        <div
          v-for="c in cards"
          :key="c.key"
          class="rounded-xl border border-n-weak p-4"
        >
          <p class="text-body-main text-n-slate-11">
            {{ t(`RAGENT.RES.USAGE_PANEL.${c.key}`) }}
          </p>
          <p class="mt-1 text-heading-2 text-n-slate-12">{{ c.value }}</p>
          <p v-if="c.estimated" class="text-xs text-n-amber-11">
            {{ t('RAGENT.RES.USAGE_PANEL.ESTIMATED') }}
          </p>
        </div>
      </div>

      <section>
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          {{ t('RAGENT.RES.USAGE_PANEL.BY_MODEL') }}
        </h2>
        <div class="overflow-x-auto rounded-xl border border-n-weak">
          <table class="w-full text-start text-body-main">
            <thead>
              <tr class="border-b border-n-weak text-n-slate-11">
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.COLUMNS.PROVIDER') }}
                </th>
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.COLUMNS.MODEL') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.USAGE_PANEL.CALLS') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.USAGE_PANEL.TOKENS') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.USAGE_PANEL.COST_ESTIMATED') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="m in byModel"
                :key="`${m.provider}-${m.model}`"
                class="border-b border-n-weak last:border-0"
              >
                <td class="px-4 py-2 text-n-slate-12">{{ m.provider }}</td>
                <td class="px-4 py-2 text-n-slate-12">{{ m.model }}</td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatNumber(m.calls) }}
                </td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatNumber(m.tokens) }}
                </td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatBRL(m.cost_usd) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          {{ t('RAGENT.RES.USAGE_PANEL.BY_DAY') }}
        </h2>
        <div class="overflow-x-auto rounded-xl border border-n-weak">
          <table class="w-full text-start text-body-main">
            <thead>
              <tr class="border-b border-n-weak text-n-slate-11">
                <th class="px-4 py-2 text-start">
                  {{ t('RAGENT.RES.USAGE_PANEL.DAY') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.USAGE_PANEL.TOKENS') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.USAGE_PANEL.COST_ESTIMATED') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="d in byDay"
                :key="d.day"
                class="border-b border-n-weak last:border-0"
              >
                <td class="px-4 py-2 text-n-slate-12">
                  {{ formatDate(d.day) }}
                </td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatNumber(d.tokens) }}
                </td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatBRL(d.cost_usd) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      <p class="text-xs text-n-slate-10">
        {{ t('RAGENT.RES.USAGE_PANEL.RATE_NOTE', { rate }) }}
      </p>
    </template>
  </div>
</template>
