<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import rtAiChat from 'dashboard/api/rtAiChat';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  chatId: { type: String, required: true },
  artifacts: { type: Array, default: () => [] },
});

const { t } = useI18n();

const IMAGE = /\.(png|jpe?g|gif|webp)$/i;
const previews = ref({});
const busyId = ref('');
const open = ref(true);

const isImage = a => IMAGE.test(a.title || '');
const kindLabel = a => {
  const key = ['dataset', 'chart', 'document', 'file'].includes(a.kind)
    ? a.kind
    : 'file';
  return t(`RAGENT.CHAT.ARTIFACTS.KIND.${key}`);
};
const extension = a => {
  const match = /\.([a-z0-9]{1,6})$/i.exec(a.title || '');
  return match ? match[1].toUpperCase() : '';
};
const formatSize = bytes => {
  if (!bytes) return '';
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
};

const loadPreview = async artifact => {
  const id = artifact.id;
  if (previews.value[id]) return;
  try {
    const { data } = await rtAiChat.artifactFile(props.chatId, id, {
      inline: true,
    });
    previews.value = { ...previews.value, [id]: URL.createObjectURL(data) };
  } catch (error) {
    // sem pré-visualização: o botão Baixar continua disponível
  }
};

watch(
  () => props.artifacts,
  list => list.filter(isImage).forEach(loadPreview),
  { immediate: true, deep: true }
);

const download = async artifact => {
  busyId.value = artifact.id;
  try {
    const { data } = await rtAiChat.artifactFile(props.chatId, artifact.id);
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = artifact.title || 'arquivo';
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  } catch (error) {
    useAlert(t('RAGENT.CHAT.ARTIFACTS.DOWNLOAD_ERROR'));
  } finally {
    busyId.value = '';
  }
};

onBeforeUnmount(() => {
  Object.values(previews.value).forEach(url => URL.revokeObjectURL(url));
});
</script>

<template>
  <section
    v-if="artifacts.length"
    class="border-t border-n-weak px-4 py-2"
    data-testid="artifact-panel"
  >
    <button
      type="button"
      class="flex w-full items-center gap-2 text-start text-heading-3 text-n-slate-12"
      :aria-expanded="open"
      @click="open = !open"
    >
      <span
        :class="open ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'"
        class="size-4"
        aria-hidden="true"
      />
      {{ t('RAGENT.CHAT.ARTIFACTS.TITLE') }} ({{ artifacts.length }})
    </button>
    <ul v-if="open" class="mt-2 grid max-h-56 gap-2 overflow-y-auto">
      <li
        v-for="a in artifacts"
        :key="a.id"
        class="flex items-center gap-3 rounded-lg bg-n-alpha-1 p-2"
      >
        <img
          v-if="previews[a.id]"
          :src="previews[a.id]"
          :alt="t('RAGENT.CHAT.ARTIFACTS.PREVIEW_ALT', { name: a.title })"
          class="size-14 shrink-0 rounded-md object-cover"
        />
        <span
          v-else
          class="i-lucide-file size-6 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        <div class="min-w-0 flex-1">
          <p class="truncate text-body-main text-n-slate-12">
            {{ a.title || t('RAGENT.CHAT.ARTIFACTS.KIND.file') }}
          </p>
          <p class="text-body-main text-n-slate-11">
            {{
              [kindLabel(a), extension(a), formatSize(a.size)]
                .filter(Boolean)
                .join(' · ')
            }}
          </p>
        </div>
        <Button
          :label="t('RAGENT.CHAT.ARTIFACTS.DOWNLOAD')"
          size="sm"
          variant="faded"
          icon="i-lucide-download"
          :is-loading="busyId === a.id"
          :disabled="busyId === a.id"
          @click="download(a)"
        />
      </li>
    </ul>
  </section>
</template>
