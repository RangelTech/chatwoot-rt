<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  sending: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  readOnly: { type: Boolean, default: false },
});
const emit = defineEmits(['send', 'stop']);

const { t } = useI18n();

const MAX_FILE_BYTES = 25 * 1024 * 1024;
const MAX_FILES = 10;

const draft = ref('');
const files = ref([]);
const picker = ref(null);

const canSend = computed(
  () =>
    !props.disabled &&
    !props.sending &&
    (draft.value.trim() || files.value.length > 0)
);

const sameFile = (a, b) =>
  a.name === b.name && a.size === b.size && a.lastModified === b.lastModified;

const addFiles = list => {
  Array.from(list || []).forEach(file => {
    if (file.size > MAX_FILE_BYTES) {
      useAlert(t('RAGENT.CHAT.ATTACH_TOO_BIG', { name: file.name }));
      return;
    }
    if (files.value.some(f => sameFile(f, file))) return;
    if (files.value.length >= MAX_FILES) {
      useAlert(t('RAGENT.CHAT.ATTACH_LIMIT', { n: MAX_FILES }));
      return;
    }
    files.value.push(file);
  });
};

const onPick = event => {
  addFiles(event.target.files);
  // permite escolher o mesmo arquivo de novo depois de remover
  event.target.value = '';
};

const onDrop = event => {
  if (!props.readOnly && !props.sending) addFiles(event.dataTransfer.files);
};

const removeFile = index => files.value.splice(index, 1);

const formatSize = bytes => {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
};

const submit = () => {
  if (!canSend.value) return;
  emit('send', { text: draft.value.trim(), files: files.value.slice() });
  draft.value = '';
  files.value = [];
};
</script>

<template>
  <footer
    class="flex flex-col gap-2 border-t border-n-weak p-3 max-md:ps-20"
    @dragover.prevent
    @drop.prevent="onDrop"
  >
    <p v-if="readOnly" class="text-body-main text-n-slate-11">
      {{ t('RAGENT.CHAT.READ_ONLY') }}
    </p>
    <template v-else>
      <ul v-if="files.length" class="flex flex-wrap gap-2">
        <li
          v-for="(file, i) in files"
          :key="`${file.name}-${file.size}-${file.lastModified}`"
          class="flex max-w-full items-center gap-2 rounded-lg bg-n-alpha-2 px-2 py-1 text-body-main text-n-slate-12"
        >
          <span class="i-lucide-paperclip size-4 shrink-0" aria-hidden="true" />
          <span class="truncate">{{ file.name }}</span>
          <span class="shrink-0 text-n-slate-11">
            {{ formatSize(file.size) }}
          </span>
          <button
            type="button"
            class="shrink-0 text-n-slate-11 hover:text-n-slate-12"
            :aria-label="t('RAGENT.CHAT.ATTACH_REMOVE', { name: file.name })"
            :disabled="sending"
            @click="removeFile(i)"
          >
            <span class="i-lucide-x size-4" aria-hidden="true" />
          </button>
        </li>
      </ul>
      <div class="flex items-end gap-2">
        <input
          ref="picker"
          type="file"
          multiple
          class="hidden"
          data-testid="chat-file-input"
          @change="onPick"
        />
        <Button
          icon="i-lucide-paperclip"
          variant="ghost"
          color="slate"
          :title="t('RAGENT.CHAT.ATTACH')"
          :aria-label="t('RAGENT.CHAT.ATTACH')"
          :disabled="sending || disabled"
          @click="picker.click()"
        />
        <textarea
          v-model="draft"
          rows="2"
          class="!mb-0 flex-1 resize-none"
          :placeholder="t('RAGENT.CHAT.PLACEHOLDER')"
          :disabled="sending"
          @keydown.enter.exact.prevent="submit"
        />
        <Button
          v-if="!sending"
          :label="t('RAGENT.CHAT.SEND')"
          :disabled="!canSend"
          @click="submit"
        />
        <Button
          v-else
          :label="t('RAGENT.CHAT.STOP')"
          color="ruby"
          @click="emit('stop')"
        />
      </div>
    </template>
  </footer>
</template>
