<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// Cadastro de provedor por OAuth (G-3). O servidor guarda PKCE/estado; aqui só se abre a URL,
// se cola a URL de retorno (authorization code) ou se mostra o código do dispositivo.
const props = defineProps({ base: { type: String, required: true } });
const emit = defineEmits(['done']);
const { axios } = window;
const { t } = useI18n();

const PROVIDERS = ['codex', 'claude', 'gemini-cli', 'github'];
const LABELS = {
  codex: 'OpenAI Codex (ChatGPT)',
  claude: 'Claude Code (Anthropic)',
  'gemini-cli': 'Gemini CLI (Google)',
  github: 'GitHub Copilot',
};
const copied = ref(false);
const copyLink = async () => {
  try {
    await navigator.clipboard.writeText(flow.value.auth_url);
    copied.value = true;
    setTimeout(() => {
      copied.value = false;
    }, 2000);
  } catch (e) {
    copied.value = false;
  }
};
const openPopup = () => {
  window.open(flow.value.auth_url, 'luar-oauth', 'width=520,height=720,noopener');
};
const provider = ref('codex');
const flow = ref(null);
const callback = ref('');
const busy = ref(false);
const message = ref('');
const failed = ref(false);

const url = action => `${props.base}/providers_oauth/${provider.value}/${action}`;
const say = (text, bad = false) => {
  message.value = text;
  failed.value = bad;
};
const errorText = error =>
  error?.response?.data?.message || t('RAGENT.RES.ERROR');

const start = async () => {
  busy.value = true;
  say('');
  try {
    const { data } = await axios.get(url('start'));
    flow.value = data;
  } catch (error) {
    flow.value = null;
    say(errorText(error), true);
  } finally {
    busy.value = false;
  }
};

const finish = async () => {
  busy.value = true;
  try {
    const { data } = await axios.post(url('finish'), {
      state: flow.value.state,
      callback_url: callback.value,
    });
    say(
      t('RAGENT.RES.GW.OAUTH.CONNECTED', {
        name: data.email || data.displayName || data.provider || '',
      })
    );
    flow.value = null;
    callback.value = '';
    emit('done');
  } catch (error) {
    say(errorText(error), true);
  } finally {
    busy.value = false;
  }
};

const poll = async () => {
  busy.value = true;
  try {
    const { data } = await axios.post(url('poll'), { state: flow.value.state });
    if (data.success) {
      say(
        t('RAGENT.RES.GW.OAUTH.CONNECTED', {
          name: data.connection?.provider || '',
        })
      );
      flow.value = null;
      emit('done');
    } else {
      say(t('RAGENT.RES.GW.OAUTH.WAITING'));
    }
  } catch (error) {
    say(errorText(error), true);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    data-testid="provider-oauth"
  >
    <h2 class="text-heading-3 text-n-slate-12">
      {{ t('RAGENT.RES.GW.OAUTH.TITLE') }}
    </h2>
    <p class="text-body-main text-n-slate-11">
      {{ t('RAGENT.RES.GW.OAUTH.HELP') }}
    </p>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="p in PROVIDERS"
        :key="p"
        type="button"
        class="rounded-xl border px-3 py-2 text-start text-body-main"
        :class="provider === p ? 'border-n-brand bg-n-alpha-2 text-n-slate-12' : 'border-n-weak text-n-slate-11'"
        :disabled="!!flow"
        @click="provider = p"
      >
        {{ LABELS[p] }}
      </button>
      <Button
        v-if="!flow"
        :label="t('RAGENT.RES.GW.OAUTH.START')"
        :disabled="busy"
        @click="start"
      />
    </div>

    <template v-if="flow && flow.flow === 'authorization_code'">
      <p class="text-body-main text-n-slate-11">
        {{ t('RAGENT.RES.GW.OAUTH.STEP_OPEN') }}
      </p>
      <div v-if="String(flow.auth_url).startsWith('https://')" class="flex flex-wrap gap-2">
        <Button :label="t('RAGENT.RES.GW.OAUTH.OPEN')" @click="openPopup" />
        <Button
          variant="faded"
          :label="copied ? t('RAGENT.RES.GW.OAUTH.COPIED') : t('RAGENT.RES.GW.OAUTH.COPY')"
          @click="copyLink"
        />
      </div>
      <p class="text-body-main text-n-slate-11">{{ t('RAGENT.RES.GW.OAUTH.STEP_PASTE') }}</p>
      <label class="text-body-main text-n-slate-11">
        {{ t('RAGENT.RES.GW.OAUTH.PASTE') }}
        <input
          v-model="callback"
          type="text"
          class="!mb-0 w-full"
          autocomplete="off"
        />
      </label>
      <Button
        :label="t('RAGENT.RES.GW.OAUTH.FINISH')"
        :disabled="busy || !callback"
        @click="finish"
      />
    </template>

    <template v-else-if="flow && flow.flow === 'device_code'">
      <p class="text-body-main text-n-slate-11">
        {{ t('RAGENT.RES.GW.OAUTH.STEP_DEVICE') }}
      </p>
      <code class="text-heading-2 text-n-slate-12">{{ flow.userCode }}</code>
      <a
        :href="flow.verificationUriComplete || flow.verificationUri"
        target="_blank"
        rel="noopener noreferrer"
        class="break-all text-n-brand underline"
      >
        {{ flow.verificationUri }}
      </a>
      <Button
        :label="t('RAGENT.RES.GW.OAUTH.CHECK')"
        :disabled="busy"
        @click="poll"
      />
    </template>

    <template v-else-if="flow && flow.flow === 'simulator'">
      <p class="text-body-main text-n-amber-11">
        {{ t('RAGENT.RES.GW.OAUTH.SIMULATOR') }}
      </p>
      <Button
        :label="t('RAGENT.RES.GW.OAUTH.AUTHORIZE_SIM')"
        :disabled="busy"
        @click="finish"
      />
    </template>

    <p
      v-if="message"
      class="text-body-main"
      :class="failed ? 'text-n-ruby-11' : 'text-n-slate-12'"
      :role="failed ? 'alert' : 'status'"
    >
      {{ message }}
    </p>
  </section>
</template>
