<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatBRL, formatNumber, USD_BRL_ESTIMATE } from './format';

// Uso e custo do gateway (G-6): só o tenant da sessão; custo é estimativa, não cobrança.
const props = defineProps({ data: { type: Object, required: true } });
const { t } = useI18n();

const list = key => (Array.isArray(props.data[key]) ? props.data[key] : []);
const tokens = row =>
  Number(row?.promptTokens || 0) + Number(row?.completionTokens || 0);
const isEmpty = computed(() => !Number(props.data.requests || 0));
const rate = computed(() => formatNumber(USD_BRL_ESTIMATE, 2));

const cards = computed(() => [
  { key: 'REQUESTS', value: formatNumber(props.data.requests) },
  { key: 'PROMPT_TOKENS', value: formatNumber(props.data.promptTokens) },
  {
    key: 'COMPLETION_TOKENS',
    value: formatNumber(props.data.completionTokens),
  },
  { key: 'ERRORS', value: formatNumber(props.data.errors) },
  { key: 'COST', value: formatBRL(props.data.cost) },
]);

const tables = computed(() => [
  { key: 'PROVIDER', rows: list('byProvider'), label: r => r.provider },
  {
    key: 'MODEL',
    rows: list('byModel'),
    label: r => `${r.provider || ''} / ${r.model || ''}`,
  },
  { key: 'COMBO', rows: list('byCombo'), label: r => r.combo || '—' },
  { key: 'DAY', rows: list('byDay'), label: r => r.day },
]);
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="provider-cost-panel">
    <p
      v-if="isEmpty"
      class="rounded-xl border border-dashed border-n-weak px-4 py-6 text-body-main text-n-slate-11"
    >
      {{ t('RAGENT.RES.GW.COST.EMPTY') }}
    </p>
    <template v-else>
      <div class="grid grid-cols-2 gap-3 md:grid-cols-5">
        <div
          v-for="c in cards"
          :key="c.key"
          class="rounded-xl border border-n-weak p-4"
        >
          <p class="text-body-main text-n-slate-11">
            {{ t(`RAGENT.RES.GW.COST.${c.key}`) }}
          </p>
          <p class="mt-1 text-heading-2 text-n-slate-12">{{ c.value }}</p>
        </div>
      </div>
      <section v-for="tb in tables" :key="tb.key">
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          {{ t(`RAGENT.RES.GW.COST.BY_${tb.key}`) }}
        </h2>
        <div class="overflow-x-auto rounded-xl border border-n-weak">
          <table class="w-full text-start text-body-main">
            <thead>
              <tr class="border-b border-n-weak text-n-slate-11">
                <th class="px-4 py-2 text-start">
                  {{ t(`RAGENT.RES.GW.COST.COL_${tb.key}`) }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.GW.COST.REQUESTS') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.GW.COST.TOKENS') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.GW.COST.ERRORS') }}
                </th>
                <th class="px-4 py-2 text-end">
                  {{ t('RAGENT.RES.GW.COST.COST') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(r, i) in tb.rows"
                :key="`${tb.key}-${i}`"
                class="border-b border-n-weak last:border-0"
              >
                <td class="px-4 py-2 text-n-slate-12">{{ tb.label(r) }}</td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatNumber(r.requests) }}
                </td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatNumber(tokens(r)) }}
                </td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatNumber(r.errors) }}
                </td>
                <td class="px-4 py-2 text-end text-n-slate-12">
                  {{ formatBRL(r.cost) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
      <p class="text-xs text-n-slate-10">
        {{ t('RAGENT.RES.GW.COST.NOTE', { rate }) }}
      </p>
    </template>
  </div>
</template>
