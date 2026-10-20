<script setup>
// Resposta do agente renderizada conforme o formato (markdown | whatsapp | text), sempre
// sanitizada em ./markdown.js. Blocos já completos mantêm o HTML e não são tocados no stream.
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  onUpdated,
  ref,
} from 'vue';
import { useI18n } from 'vue-i18n';
import rtAiChat from 'dashboard/api/rtAiChat';
import { getRenderer, normalizeFormat } from './markdown';

const props = defineProps({
  text: { type: String, default: '' },
  format: { type: String, default: 'markdown' },
  chatId: { type: String, default: '' },
  artifacts: { type: Array, default: () => [] },
});

const { t } = useI18n();
const root = ref(null);
const previews = new Map();
const pending = new Set();

const fmt = computed(() => normalizeFormat(props.format));
const blocks = computed(() =>
  getRenderer().renderBlocks(props.text, {
    format: fmt.value,
    labels: {
      copy: t('RAGENT.CHAT.MARKDOWN.COPY'),
      copied: t('RAGENT.CHAT.MARKDOWN.COPIED'),
    },
  })
);

const baseName = value =>
  String(value || '')
    .split('/')
    .pop()
    .trim()
    .toLowerCase();

const findArtifact = name => {
  const wanted = baseName(name);
  return props.artifacts.find(
    a => String(a.id) === name || baseName(a.title) === wanted
  );
};

const resolveImages = async () => {
  if (!root.value || !props.chatId) return;
  const images = root.value.querySelectorAll(
    'img[data-artifact-ref]:not([src])'
  );
  await Promise.all(
    Array.from(images).map(async img => {
      const artifact = findArtifact(img.dataset.artifactRef);
      if (!artifact) return;
      const key = String(artifact.id);
      if (!previews.has(key) && !pending.has(key)) {
        pending.add(key);
        try {
          const { data } = await rtAiChat.artifactFile(props.chatId, key, {
            inline: true,
          });
          previews.set(key, URL.createObjectURL(data));
        } catch (error) {
          // sem pré-visualização: o texto alternativo continua visível
        } finally {
          pending.delete(key);
        }
      }
      if (previews.has(key) && img.isConnected) img.src = previews.get(key);
    })
  );
};

const copy = async button => {
  const code = button.closest('.rt-md-code')?.querySelector('pre code');
  if (!code) return;
  try {
    await navigator.clipboard.writeText(code.textContent);
    const original = button.textContent;
    button.textContent = t('RAGENT.CHAT.MARKDOWN.COPIED');
    setTimeout(() => {
      button.textContent = original;
    }, 1500);
  } catch (error) {
    // navegador sem permissão de área de transferência: nada a fazer
  }
};

const onClick = event => {
  const button = event.target.closest?.('[data-copy-code]');
  if (button) copy(button);
};

const refresh = () => nextTick(resolveImages);
onMounted(refresh);
onUpdated(refresh);
onBeforeUnmount(() => {
  previews.forEach(url => URL.revokeObjectURL(url));
  previews.clear();
});
</script>

<template>
  <div
    ref="root"
    class="rt-md"
    :class="{ 'rt-md-plain': fmt !== 'markdown' }"
    @click="onClick"
  >
    <!-- eslint-disable-next-line vue/no-v-html -->
    <div v-for="(html, i) in blocks" :key="i" v-html="html" />
  </div>
</template>

<style lang="scss">
.rt-md {
  @apply break-words text-n-slate-12;

  > div > * + *,
  > div + div {
    @apply mt-2;
  }

  p,
  li {
    @apply leading-relaxed;
  }

  h1,
  h2,
  h3,
  h4,
  h5,
  h6 {
    @apply mt-3 mb-1 font-semibold text-n-slate-12;
  }
  h1 {
    @apply text-lg;
  }
  h2 {
    @apply text-base;
  }
  h3,
  h4,
  h5,
  h6 {
    @apply text-sm;
  }

  ul,
  ol {
    @apply ps-5;
  }
  ul {
    list-style: disc;
  }
  ol {
    list-style: decimal;
  }
  li + li {
    @apply mt-1;
  }

  a {
    @apply text-n-brand underline;
    overflow-wrap: anywhere;
  }

  blockquote {
    @apply border-s-2 border-n-weak ps-3 text-n-slate-11;
  }

  hr {
    @apply my-3 border-n-weak;
  }

  code {
    @apply rounded bg-n-alpha-2 px-1 py-0.5 font-mono text-[0.85em];
  }

  .rt-md-code {
    @apply overflow-hidden rounded-xl border border-n-weak;

    .rt-md-code-bar {
      @apply flex items-center justify-between bg-n-alpha-2 px-3 py-1 text-xs text-n-slate-11;
    }
    .rt-md-copy {
      @apply rounded-md px-2 py-0.5 text-xs text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12;
    }
    pre {
      @apply m-0 overflow-x-auto p-3;
    }
    pre code {
      @apply bg-transparent p-0 text-[0.85em];
      white-space: pre;
    }
  }

  table {
    @apply block max-w-full overflow-x-auto border-collapse text-sm;
  }
  th,
  td {
    @apply border border-n-weak px-3 py-1.5 text-start;
  }
  th {
    @apply bg-n-alpha-2 font-semibold;
  }

  .rt-md-img {
    @apply h-auto max-w-full rounded-lg;
  }
}

.rt-md-plain {
  white-space: pre-wrap;

  p {
    margin: 0;
  }
}
</style>
