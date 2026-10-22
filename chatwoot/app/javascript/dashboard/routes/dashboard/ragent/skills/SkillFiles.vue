<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

// Spec 11 §4: arquivos da skill (cardápio, tabela de preços...). 10 MB por arquivo; 500 MB por empresa.
const props = defineProps({
  base: { type: String, required: true },
  skillId: { type: String, required: true },
});
const { t } = useI18n();
const { axios } = window;

const files = ref([]);
const used = ref(0);
const limit = ref(0);
const busy = ref(false);
const picker = ref(null);
const MAX = 10 * 1024 * 1024;

const url = () => `${props.base}/skills/company/${props.skillId}/files`;
const size = b =>
  b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`;

const load = async () => {
  try {
    const { data } = await axios.get(url());
    files.value = data.files || [];
    used.value = data.used_bytes || 0;
    limit.value = data.limit_bytes || 0;
  } catch (e) {
    files.value = [];
  }
};

const toB64 = file =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(',')[1] || '');
    r.onerror = reject;
    r.readAsDataURL(file);
  });

const upload = async list => {
  busy.value = true;
  for (const file of Array.from(list || [])) {
    if (file.size > MAX) {
      useAlert(t('RAGENT.SKILLS.FILE_TOO_BIG', { name: file.name }));
    } else {
      try {
        // eslint-disable-next-line no-await-in-loop
        await axios.post(url(), {
          name: file.name,
          mime: file.type,
          content_b64: await toB64(file),
        });
      } catch (e) {
        useAlert(e?.response?.data?.message || t('RAGENT.SKILLS.FILE_ERROR', { name: file.name }));
      }
    }
  }
  busy.value = false;
  await load();
};

const remove = async f => {
  await axios.delete(`${url()}/${f.id}`);
  await load();
};

onMounted(load);
</script>

<template>
  <section
    class="flex flex-col gap-2 rounded-xl border border-n-weak p-3"
    @dragover.prevent
    @drop.prevent="upload($event.dataTransfer.files)"
  >
    <header class="flex items-center gap-2">
      <h3 class="text-heading-3 text-n-slate-12">{{ t('RAGENT.SKILLS.FILES') }}</h3>
      <span class="ms-auto text-body-main text-n-slate-11">
        {{ size(used) }} / {{ size(limit) }}
      </span>
      <button
        type="button"
        class="rounded-md border border-n-weak px-2 py-1 text-sm"
        :disabled="busy"
        @click="picker.click()"
      >
        {{ t('RAGENT.SKILLS.FILES_ADD') }}
      </button>
      <input
        ref="picker"
        type="file"
        multiple
        class="hidden"
        @change="upload($event.target.files); $event.target.value = ''"
      />
    </header>
    <p class="text-body-main text-n-slate-11">{{ t('RAGENT.SKILLS.FILES_HELP') }}</p>
    <ul v-if="files.length" class="divide-y divide-n-weak">
      <li v-for="f in files" :key="f.id" class="flex items-center gap-2 py-1 text-body-main">
        <span class="truncate text-n-slate-12">{{ f.name }}</span>
        <span class="text-n-slate-11">{{ size(f.size_bytes) }}</span>
        <button type="button" class="ms-auto text-n-ruby-11" @click="remove(f)">
          {{ t('RAGENT.SKILLS.FILES_REMOVE') }}
        </button>
      </li>
    </ul>
  </section>
</template>
