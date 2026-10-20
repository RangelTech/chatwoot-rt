<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { usePolicy } from 'dashboard/composables/usePolicy';
import rtAiChat from 'dashboard/api/rtAiChat';
import Button from 'dashboard/components-next/button/Button.vue';
import { AI_PERMISSIONS } from 'dashboard/constants/permissions';
import { streamChat } from './useChatStream';
import ChatComposer from './ChatComposer.vue';
import ChatHistoryList from './ChatHistoryList.vue';
import ApprovalCard from './ApprovalCard.vue';
import ArtifactPanel from './ArtifactPanel.vue';
import MessageFeedback from './MessageFeedback.vue';
import ChatMarkdown from './ChatMarkdown.vue';
import ThinkingPanel from './ThinkingPanel.vue';
import { normalizeFormat } from './markdown';
import { isWorking, parseSubagents, upsertStep } from './progress';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { checkPermissions } = usePolicy();
const canRun = computed(() => checkPermissions([AI_PERMISSIONS.CHAT_RUN]));
const canDecide = computed(() => checkPermissions(['ai.approvals.decide']));

const chats = ref([]);
// Celular: o histórico abre numa gaveta (a lateral fixa só existe a partir de md).
const historyOpen = ref(false);
const templates = ref([]);
const templateId = ref('');
const messages = ref([]);
const chatId = ref(route.params.chatId || '');
const artifacts = ref([]);
const approvals = ref([]);
const runId = ref('');
const sending = ref(false);
const steps = ref([]);
const thinking = ref('');
const subagents = ref({ active: 0, total: 0 });
// Formato em que o agente escreve (markdown | whatsapp | text): vem do chat, do início da run e do `done`.
const chatFormat = ref('markdown');
const loading = ref(true);
const forbidden = ref(false);
const scroller = ref(null);
let controller = null;

const hasTemplates = computed(() => templates.value.length > 0);
const scrollDown = async () => {
  await nextTick();
  if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight;
};

const loadChats = async () => {
  const { data } = await rtAiChat.get();
  chats.value = (data.chats || data || []).filter(c => c.source !== 'channel');
};

const mapMessages = data =>
  (data.messages || data || []).map(m => ({
    id: m.id,
    role: m.role,
    content: m.content,
    format: chatFormat.value,
    attachments: m.attachments || [],
  }));

const loadArtifacts = async id => {
  try {
    const { data } = await rtAiChat.artifacts(id);
    artifacts.value = data || [];
  } catch (error) {
    artifacts.value = [];
  }
};

// Aprovações que ficaram pendentes (ex.: recarregou a página no meio do pedido).
const loadPendingApprovals = async id => {
  try {
    const { data } = await rtAiChat.pendingApprovals();
    approvals.value = (data || []).filter(a => a.chat_id === id);
  } catch (error) {
    approvals.value = [];
  }
};

const openChat = async id => {
  historyOpen.value = false;
  chatId.value = id;
  artifacts.value = [];
  approvals.value = [];
  const { data } = await rtAiChat.messages(id);
  messages.value = mapMessages(data);
  loadArtifacts(id);
  loadPendingApprovals(id);
  const chat = chats.value.find(c => c.id === id);
  if (chat?.template_id) templateId.value = chat.template_id;
  chatFormat.value = normalizeFormat(chat?.output_format);
  messages.value = mapMessages(data);
  router.replace({ name: 'ragent_chat_detail', params: { chatId: id } });
  scrollDown();
};

const newChat = () => {
  historyOpen.value = false;
  chatId.value = '';
  chatFormat.value = 'markdown';
  messages.value = [];
  artifacts.value = [];
  approvals.value = [];
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

const showThinking = computed(() =>
  isWorking({
    sending: sending.value,
    lastContent: messages.value[messages.value.length - 1]?.content,
    steps: steps.value,
    subagents: subagents.value,
  })
);

const handleEvent = (event, data) => {
  const last = messages.value[messages.value.length - 1];
  if (event === 'chat' && data.chat_id) {
    chatId.value = data.chat_id;
    runId.value = data.run_id || '';
    if (data.output_format) {
      chatFormat.value = normalizeFormat(data.output_format);
      if (last) last.format = chatFormat.value;
    }
  } else if (event === 'artifact' && data.artifact_id) {
    if (!artifacts.value.some(a => a.id === data.artifact_id)) {
      artifacts.value.push({
        id: data.artifact_id,
        kind: data.kind,
        title: data.title,
      });
    }
  } else if (event === 'approval_required' && data.approval_id) {
    if (!approvals.value.some(a => a.approval_id === data.approval_id)) {
      approvals.value.push({ ...data, chat_id: chatId.value });
    }
  } else if (event === 'token') {
    last.content += data.text || '';
  } else if (event === 'thinking') {
    thinking.value = data.text || '';
  } else if (event === 'step') {
    steps.value = upsertStep(steps.value, data);
  } else if (event === 'subagents') {
    subagents.value = parseSubagents(data);
  } else if (event === 'done') {
    if (data.format) {
      chatFormat.value = normalizeFormat(data.format);
      last.format = chatFormat.value;
    }
    if (!last.content) last.content = data.text || '';
  } else if (event === 'error') {
    last.content = data.detail || t('RAGENT.CHAT.ERROR');
    last.error = true;
  }
  scrollDown();
};

const send = async ({ text, files }) => {
  if (sending.value) return;
  messages.value.push({
    role: 'user',
    content: text,
    attachments: files.map(f => ({ name: f.name, kind: 'file' })),
  });
  messages.value.push({ role: 'assistant', content: '' });
  sending.value = true;
  steps.value = [];
  thinking.value = '';
  subagents.value = { active: 0, total: 0 };
  runId.value = '';
  controller = new AbortController();
  try {
    await streamChat({
      message: text,
      chatId: chatId.value,
      templateId: templateId.value,
      files,
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
    thinking.value = '';
    subagents.value = { active: 0, total: 0 };
    await syncAfterRun();
  }
};

// Recarrega do servidor para trazer os ids das respostas (necessários ao feedback) e os arquivos.
const syncAfterRun = async () => {
  const id = chatId.value;
  if (!id) return;
  const last = messages.value[messages.value.length - 1];
  if (!last?.error) {
    try {
      const { data } = await rtAiChat.messages(id);
      messages.value = mapMessages(data);
    } catch (error) {
      // mantém o que já está na tela
    }
  }
  loadArtifacts(id);
};

const stop = async () => {
  const id = runId.value;
  controller?.abort();
  if (id) {
    try {
      await rtAiChat.cancel(id);
    } catch (error) {
      // a conexão já foi encerrada; o servidor também expira a execução
    }
  }
};
</script>

<template>
  <div class="flex h-full w-full overflow-hidden bg-n-surface-1">
    <aside
      class="hidden md:flex w-64 shrink-0 flex-col border-r border-n-weak p-3"
    >
      <ChatHistoryList
        :chats="chats"
        :chat-id="chatId"
        @new="newChat"
        @open="openChat"
      />
    </aside>

    <div
      v-if="historyOpen"
      class="fixed inset-0 z-50 flex md:hidden"
      data-testid="chat-history-drawer"
    >
      <div
        class="flex h-full w-72 max-w-[85%] flex-col gap-2 bg-n-surface-1 p-3 shadow-xl"
        role="dialog"
        :aria-label="t('RAGENT.CHAT.HISTORY')"
      >
        <div class="flex items-center justify-between">
          <h2 class="text-heading-3 text-n-slate-12">
            {{ t('RAGENT.CHAT.HISTORY') }}
          </h2>
          <Button
            icon="i-lucide-x"
            variant="ghost"
            color="slate"
            size="sm"
            :aria-label="t('RAGENT.CHAT.HISTORY_CLOSE')"
            @click="historyOpen = false"
          />
        </div>
        <ChatHistoryList
          :chats="chats"
          :chat-id="chatId"
          @new="newChat"
          @open="openChat"
        />
      </div>
      <button
        type="button"
        class="flex-1 bg-n-alpha-black1 backdrop-blur-sm"
        :aria-label="t('RAGENT.CHAT.HISTORY_CLOSE')"
        @click="historyOpen = false"
      />
    </div>

    <section class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex flex-wrap items-center gap-3 border-b border-n-weak px-4 py-3"
      >
        <Button
          class="md:!hidden"
          icon="i-lucide-history"
          variant="faded"
          color="slate"
          size="sm"
          data-testid="chat-history-toggle"
          :label="t('RAGENT.CHAT.HISTORY')"
          :aria-expanded="historyOpen"
          @click="historyOpen = true"
        />
        <h1 class="text-heading-2 text-n-slate-12">
          {{ t('RAGENT.CHAT.TITLE') }}
        </h1>
        <span
          class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-body-main text-n-slate-11"
        >
          {{ t('RAGENT.CHAT.NOT_SENT_TO_CUSTOMER') }}
        </span>
        <select
          v-if="hasTemplates"
          v-model="templateId"
          class="!mb-0 w-full md:ms-auto md:w-64"
          :disabled="Boolean(chatId)"
          :aria-label="t('RAGENT.CHAT.AGENT')"
        >
          <option value="" disabled>{{ t('RAGENT.CHAT.PICK_AGENT') }}</option>
          <option v-for="tp in templates" :key="tp.id" :value="tp.id">
            {{ tp.name }}
          </option>
        </select>
      </header>

      <p v-if="loading" class="p-6 text-n-slate-11">
        {{ t('RAGENT.CHAT.LOADING') }}
      </p>
      <p v-else-if="forbidden" class="p-6 text-n-slate-11">
        {{ t('RAGENT.CHAT.FORBIDDEN') }}
      </p>
      <p v-else-if="!hasTemplates && !chatId" class="p-6 text-n-slate-11">
        {{ t('RAGENT.CHAT.NO_AGENTS') }}
      </p>

      <div ref="scroller" class="flex-1 space-y-3 overflow-y-auto p-4">
        <div
          v-for="(m, i) in messages"
          :key="i"
          class="flex"
          :class="m.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            v-if="m.role === 'user' || m.content || m.error"
            class="max-w-[80%] rounded-2xl px-4 py-2 text-body-main"
            :class="[
              m.role === 'user' ? 'whitespace-pre-wrap' : 'min-w-0',
              m.role === 'user'
                ? 'bg-n-brand text-white'
                : 'bg-n-alpha-2 text-n-slate-12',
              m.error ? 'border border-n-ruby-9' : '',
            ]"
          >
            <ul
              v-if="m.attachments && m.attachments.length"
              class="mb-1 flex flex-wrap gap-1"
            >
              <li
                v-for="(att, j) in m.attachments"
                :key="j"
                class="flex items-center gap-1 rounded-md bg-n-alpha-2 px-2 py-0.5 text-body-main"
              >
                <span class="i-lucide-paperclip size-3" aria-hidden="true" />
                {{ att.name }}
              </li>
            </ul>
            <template v-if="m.role === 'user' || m.error">{{
              m.content
            }}</template>
            <ChatMarkdown
              v-else
              :text="m.content"
              :format="m.format || chatFormat"
              :chat-id="chatId"
              :artifacts="artifacts"
            />
            <MessageFeedback
              v-if="
                m.role === 'assistant' && m.id && m.content && canRun && chatId
              "
              :key="m.id"
              :chat-id="chatId"
              :message-id="m.id"
            />
          </div>
        </div>
        <ApprovalCard
          v-for="ap in approvals"
          :key="ap.approval_id"
          :approval="ap"
          :can-decide="canDecide"
        />
        <ThinkingPanel
          v-if="showThinking"
          :thinking="thinking"
          :steps="steps"
          :subagents="subagents"
        />
      </div>

      <ArtifactPanel v-if="chatId" :chat-id="chatId" :artifacts="artifacts" />

      <ChatComposer
        :sending="sending"
        :disabled="!chatId && !templateId"
        :read-only="!canRun"
        @send="send"
        @stop="stop"
      />
    </section>
  </div>
</template>
