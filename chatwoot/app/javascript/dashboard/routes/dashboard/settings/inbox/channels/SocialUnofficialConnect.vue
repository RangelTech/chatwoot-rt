<script setup>
import { ref, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import NextButton from 'dashboard/components-next/button/Button.vue';
import InboxesAPI from 'dashboard/api/inboxes';
import PageHeader from '../../SettingsSubPageHeader.vue';

// Produto-10 (25/08/2026): mesmo padrao do navegador remoto do produto-08
// (agent-platform/frontend/src/components/ContasIA.tsx) -- aqui a
// credencial capturada no final e um jar de cookies, nao um par
// code/state. O admin loga normal (usuario/senha/2FA) numa tela espelhada
// via WebSocket; nao existe campo de usuario/senha nesta tela, o Chatwoot
// nunca ve a credencial em texto puro.
const props = defineProps({
  provider: { type: String, required: true }, // 'instagram_web' | 'facebook_web'
  title: { type: String, required: true },
  description: { type: String, required: true },
});

const STEP = { START: 'start', ABRINDO: 'abrindo', NAVEGADOR: 'navegador', CONECTADO: 'conectado' };

const step = ref(STEP.START);
const nome = ref('');
const frame = ref('');
const erro = ref('');
const inboxId = ref(null);
const wsRef = ref(null);
const { t } = useI18n();
const router = useRouter();

const NAV_W = 1280;
const NAV_H = 800;

const conectar = async () => {
  step.value = STEP.ABRINDO;
  erro.value = '';
  try {
    const { data } = await InboxesAPI.iniciarSocialUnofficial(props.provider);
    step.value = STEP.NAVEGADOR;

    const ws = new WebSocket(data.ws_url);
    wsRef.value = ws;
    ws.onmessage = async evento => {
      const msg = JSON.parse(evento.data);
      if (msg.type === 'frame') {
        frame.value = `data:image/jpeg;base64,${msg.data}`;
      } else if (msg.type === 'done') {
        try {
          const resp = await InboxesAPI.concluirSocialUnofficial(
            props.provider,
            msg.cookies,
            nome.value
          );
          inboxId.value = resp.data.id;
          step.value = STEP.CONECTADO;
        } catch (e) {
          erro.value = e?.response?.data?.error || t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.ERROR_MESSAGE');
          step.value = STEP.START;
        }
      } else if (msg.type === 'erro') {
        erro.value = msg.mensagem;
        step.value = STEP.START;
      }
    };
    ws.onerror = () => {
      erro.value = t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.ERROR_MESSAGE');
      step.value = STEP.START;
    };
  } catch (e) {
    erro.value = e?.response?.data?.error || t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.ERROR_MESSAGE');
    step.value = STEP.START;
  }
};

const enviarMouse = (e, clique) => {
  const ws = wsRef.value;
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  const rect = e.currentTarget.getBoundingClientRect();
  const x = Math.round(((e.clientX - rect.left) / rect.width) * NAV_W);
  const y = Math.round(((e.clientY - rect.top) / rect.height) * NAV_H);
  ws.send(JSON.stringify({ type: 'mouse', x, y, click: clique }));
};

const enviarTecla = e => {
  const ws = wsRef.value;
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  e.preventDefault();
  if (e.key.length === 1) ws.send(JSON.stringify({ type: 'key', text: e.key }));
  else ws.send(JSON.stringify({ type: 'key', key: e.key }));
};

const continuarSetup = () => {
  router.replace({ name: 'settings_inboxes_add_agents', params: { page: 'new', inbox_id: inboxId.value } });
};

onBeforeUnmount(() => wsRef.value?.close());
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader :header-title="title" :header-content="description" />

    <div v-if="step === STEP.START" class="flex flex-col gap-4 max-w-xl">
      <p class="text-xs text-n-amber-9">
        {{ t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.RISK_WARNING') }}
      </p>
      <label>
        {{ t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.INBOX_NAME') }}
        <input v-model="nome" type="text" :placeholder="title" />
      </label>
      <p v-if="erro" class="text-n-ruby-9">{{ erro }}</p>
      <NextButton solid blue :label="t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.SUBMIT_BUTTON')" @click="conectar" />
    </div>

    <div v-else-if="step === STEP.ABRINDO" class="flex flex-col gap-4 max-w-xl">
      <p>{{ t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.OPENING') }}</p>
    </div>

    <div v-else-if="step === STEP.NAVEGADOR" class="space-y-2">
      <p class="text-sm font-medium text-n-slate-12">
        {{ t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.LOGIN_HINT') }}
      </p>
      <div
        tabindex="0"
        class="max-w-3xl overflow-hidden rounded-2xl border border-n-weak outline-none focus:ring-2 focus:ring-n-brand"
        @keydown="enviarTecla"
      >
        <img
          v-if="frame"
          :src="frame"
          alt="Tela de login"
          class="w-full cursor-pointer select-none"
          @click="e => enviarMouse(e, true)"
          @mousemove="e => enviarMouse(e, false)"
        />
        <div v-else class="flex h-64 items-center justify-center text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.OPENING') }}
        </div>
      </div>
      <p class="text-xs text-n-slate-11">
        {{ t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.LOGIN_TIP') }}
      </p>
    </div>

    <div v-else class="flex flex-col gap-4 max-w-xl">
      <p>{{ t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.CONNECTED') }}</p>
      <NextButton type="button" solid blue :label="t('INBOX_MGMT.ADD.SOCIAL_UNOFFICIAL.CONTINUE_BUTTON')" @click="continuarSetup" />
    </div>
  </div>
</template>
