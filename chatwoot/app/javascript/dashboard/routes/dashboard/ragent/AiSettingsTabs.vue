<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';

// Spec 11 §11: abas de Configurações -> Inteligência artificial.
const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const TABS = [
  ['providers', 'PROVIDERS'],
  ['inboxes', 'INBOXES'],
  ['combos', 'COMBOS'],
  ['credentials', 'CREDENTIALS'],
  ['environment', 'ENVIRONMENT'],
  ['integrations', 'INTEGRATIONS'],
  ['quotas', 'QUOTAS'],
  ['requests', 'ADVANCED'],
];
const current = computed(() => String(route.name || '').replace('ragent_', ''));
const go = key =>
  router.push({ name: `ragent_${key}`, params: route.params });
</script>

<template>
  <nav class="flex flex-wrap gap-2" role="tablist">
    <button
      v-for="[key, label] in TABS"
      :key="key"
      type="button"
      role="tab"
      :aria-selected="current === key"
      class="px-3 py-1 text-sm rounded-full border"
      :class="
        current === key
          ? 'bg-n-brand text-white border-n-brand'
          : 'border-n-weak text-n-slate-11'
      "
      @click="go(key)"
    >
      {{ t(`RAGENT.MENU.${label}`) }}
    </button>
  </nav>
</template>
