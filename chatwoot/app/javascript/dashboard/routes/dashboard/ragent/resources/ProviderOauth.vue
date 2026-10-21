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
    <div class="flex gap-2">
      <select v-model="provider" class="!mb-0 flex-1" :disabled="!!flow">
        <option v-for="p in PROVIDERS" :key="p" :value="p">{{ p }}</option>
      </select>
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
      <a
        v-if="String(flow.auth_url).startsWith('https://')"
        :href="flow.auth_url"
        target="_blank"
        rel="noopener noreferrer"
        class="break-all text-n-brand underline"
      >
        {{ t('RAGENT.RES.GW.OAUTH.OPEN') }}
      </a>
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
