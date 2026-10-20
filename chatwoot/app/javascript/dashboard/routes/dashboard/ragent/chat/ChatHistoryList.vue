<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  chats: { type: Array, default: () => [] },
  chatId: { type: String, default: '' },
});
const emit = defineEmits(['new', 'open']);
const { t } = useI18n();
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-2">
    <Button
      :label="t('RAGENT.CHAT.NEW')"
      size="sm"
      class="w-full"
      @click="emit('new')"
    />
    <ul class="flex-1 overflow-y-auto" data-testid="chat-history-list">
      <li v-for="c in chats" :key="c.id">
        <button
          type="button"
          class="w-full truncate rounded-lg px-3 py-2 text-start text-body-main hover:bg-n-alpha-2"
          :class="
            c.id === chatId ? 'bg-n-alpha-2 text-n-slate-12' : 'text-n-slate-11'
          "
          @click="emit('open', c.id)"
        >
          {{ c.title || t('RAGENT.CHAT.UNTITLED') }}
        </button>
      </li>
    </ul>
  </div>
</template>
