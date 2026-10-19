<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import rtAiChat from 'dashboard/api/rtAiChat';
import Button from 'dashboard/components-next/button/Button.vue';
import { streamChat } from './useChatStream';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const chats = ref([]);
const templates = ref([]);
const templateId = ref('');
const messages = ref([]);
const chatId = ref(route.params.chatId || '');
const draft = ref('');
const sending = ref(false);
const steps = ref([]);
const loading = ref(true);
const forbidden = ref(false);
const scroller = ref(null);
let controller = null;

const hasTemplates = computed(() => templates.value.length > 0);
const canSend = computed(
  () => draft.value.trim() && !sending.value && (chatId.value || templateId.value)
);

const scrollDown = async () => {
  await nextTick();
  if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
};

const loadChats = async () => {
  const { data } = await rtAiChat.get();
  chats.value = (data.chats || data || []).filter(c => c.source !== 'channel');
};

const openChat = async id => {
  chatId.value = id;
  const { data } = await rtAiChat.messages(id);
  messages.value = (data.messages || data || []).map(m => ({
    role: m.role,
    content: m.content,
  }));
  const chat = chats.value.find(c => c.id === id);
  if (chat?.template_id) templateId.value = chat.template_id;
  router.replace({ name: 'ragent_chat_detail', params: { chatId: id } });
  scrollDown();
};

const newChat = () => {
  chatId.value = '';
  messages.value = [];
  router.replace({ name: 'ragent_chat' });
};

onMounted(async () => {
  try {
    const [, tpl] = await Promise.all([loadChats(), rtAiChat.templates()]);
    templates.value = tpl.data || [];
    if (!templateId.value && templates.value.length === 1) {
      templateId.value = templates.value[0].id;
    }
    if (chatId.value) await openChat(chatId.value);
  } catch (error) {
    forbidden.value = true;
  } finally {
    loading.value = false;
  }
});

const handleEvent = (event, data) => {
  const last = messages.value[messages.value.length - 1];
  if (event === 'chat' && data.chat_id) {
    chatId.value = data.chat_id;
  } else if (event === 'token') {
    last.content += data.text || '';
  } else if (event === 'step') {
    steps.value = [data.label].filter(Boolean);
  } else if (event === 'done') {
    if (!last.content) last.content = data.text || '';
  } else if (event === 'error') {
    last.content = data.detail || t('RAGENT.CHAT.ERROR');
    last.error = true;
  }
  scrollDown();
};

const send = async () => {
  if (!canSend.value) return;
  const text = draft.value.trim();
  draft.value = '';
  messages.value.push({ role: 'user', content: text });
  messages.value.push({ role: 'assistant', content: '' });
  sending.value = true;
  steps.value = [];
  controller = new AbortController();
  try {
    await streamChat({
      message: text,
      chatId: chatId.value,
      templateId: templateId.value,
      signal: controller.signal,
      onEvent: handleEvent,
    });
    await loadChats();
    if (chatId.value && route.name !== 'ragent_chat_detail') {
      router.replace({
        name: 'ragent_chat_detail',
        params: { chatId: chatId.value },
      });
    }
  } catch (error) {
    if (error.name !== 'AbortError') useAlert(t('RAGENT.CHAT.ERROR'));
  } finally {
    sending.value = false;
    steps.value = [];
  }
};

const stop = () => controller?.abort();
</script>

<template>
  <div class="flex h-full w-full overflow-hidden bg-n-surface-1">
    <aside
      class="hidden md:flex w-64 shrink-0 flex-col border-r border-n-weak p-3 gap-2"
    >
      <Button
        :label="t('RAGENT.CHAT.NEW')"
        size="sm"
        class="w-full"
        @click="newChat"
      />
      <ul class="flex-1 overflow-y-auto">
        <li v-for="c in chats" :key="c.id">
          <button
            type="button"
            class="w-full truncate rounded-lg px-3 py-2 text-start text-body-main hover:bg-n-alpha-2"
            :class="c.id === chatId ? 'bg-n-alpha-2 text-n-slate-12' : 'text-n-slate-11'"
            @click="openChat(c.id)"
          >
            {{ c.title || t('RAGENT.CHAT.UNTITLED') }}
          </button>
        </li>
      </ul>
    </aside>

    <section class="flex min-w-0 flex-1 flex-col">
      <header class="flex flex-wrap items-center gap-3 border-b border-n-weak px-4 py-3">
        <h1 class="text-heading-2 text-n-slate-12">
          {{ t('RAGENT.CHAT.TITLE') }}
        </h1>
        <span class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-body-main text-n-slate-11">
          {{ t('RAGENT.CHAT.NOT_SENT_TO_CUSTOMER'
