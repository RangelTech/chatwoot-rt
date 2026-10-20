<script setup>
// Painel recolhível "Pensando…": raciocínio resumido, passos em linguagem amigável e o contador
// de subagentes em tempo real. Só texto vindo do stream (já sem nomes internos).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  thinking: { type: String, default: '' },
  steps: { type: Array, default: () => [] },
  subagents: { type: Object, default: () => ({ active: 0, total: 0 }) },
});

const { t } = useI18n();
const open = ref(true);

const active = computed(() => Number(props.subagents?.active) || 0);
const total = computed(() => Number(props.subagents?.total) || 0);
const finished = computed(() => Math.max(0, total.value - active.value));
const lastSteps = computed(() => props.steps.slice(-8));
const hasDetails = computed(
  () => Boolean(props.thinking) || props.steps.length > 0
);
</script>

<template>
  <section
    class="rounded-xl border border-n-weak bg-n-alpha-1 px-3 py-2 text-body-main text-n-slate-11"
    aria-live="polite"
    data-testid="thinking-panel"
  >
    <button
      type="button"
      class="flex w-full items-center gap-2 text-start"
      :aria-expanded="open"
      :aria-label="
        open ? t('RAGENT.CHAT.THINKING.HIDE') : t('RAGENT.CHAT.THINKING.SHOW')
      "
      :disabled="!hasDetails"
      @click="open = !open"
    >
      <span
        class="i-lucide-loader-circle size-4 animate-spin"
        aria-hidden="true"
      />
      <span class="font-medium text-n-slate-12">
        {{ t('RAGENT.CHAT.THINKING.TITLE') }}
      </span>
      <span
        v-if="total > 0"
        class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-n-slate-12"
        data-testid="subagents-counter"
      >
        {{ t('RAGENT.CHAT.THINKING.SUBAGENTS', { n: active }, active) }}
        <span v-if="total > 1" class="text-n-slate-11">
          ·
          {{
            t('RAGENT.CHAT.THINKING.SUBAGENTS_PROGRESS', {
              done: finished,
              total,
            })
          }}
        </span>
      </span>
      <span
        v-if="hasDetails"
        class="ms-auto size-4"
        :class="open ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        aria-hidden="true"
      />
    </button>

    <div v-if="open && hasDetails" class="mt-2 flex flex-col gap-2">
      <p v-if="thinking" class="italic" data-testid="thinking-text">
        {{ thinking }}
      </p>
      <ul
        v-if="lastSteps.length"
        class="flex flex-col gap-1"
        :aria-label="t('RAGENT.CHAT.THINKING.STEPS')"
      >
        <li
          v-for="(s, i) in lastSteps"
          :key="i"
          class="flex items-center gap-2"
        >
          <span
            class="size-3.5 shrink-0"
            :class="{
              'i-lucide-loader-circle animate-spin': s.status === 'start',
              'i-lucide-check text-n-teal-10': s.status === 'done',
              'i-lucide-circle-alert text-n-ruby-9': s.status === 'error',
            }"
            aria-hidden="true"
          />
          <span class="truncate">{{ s.label }}</span>
        </li>
      </ul>
    </div>
  </section>
</template>
