<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

// Spec 11 §26: computadores conectados (lista online/offline e assistente de 3 passos).
const { t } = useI18n();
const { axios } = window;
const route = useRoute();
const base = computed(
  () => `/api/v1/accounts/${route.params.accountId}/rt_ai/hosts`
);
const HUB = 'https://conector.rangeltech.net';

const hosts = ref([]);
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);
let timer = null;

const wizard = ref(null); // { step, name, os, code, id }
const form = ref({ name: '', os: 'windows' });
const results = ref({});
const countdown = ref(0);
let tick = null;

const load = async () => {
  try {
    const { data } = await axios.get(base.value);
    hosts.value = data.hosts || [];
    failed.value = false;
    // o assistente avança sozinho quando o computador aparece online
    if (wizard.value?.step === 3) {
      const mine = hosts.value.find(h => h.id === wizard.value.id);
      if (mine?.online) wizard.value = { ...wizard.value, step: 4 };
    }
  } catch (e) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  load();
  timer = setInterval(load, 15000);
});
onBeforeUnmount(() => {
  clearInterval(timer);
  clearInterval(tick);
});

const startCountdown = seconds => {
  clearInterval(tick);
  countdown.value = seconds;
  tick = setInterval(() => {
    countdown.value = Math.max(0, countdown.value - 1);
  }, 1000);
};

const create = async () => {
  if (!form.value.name.trim()) return;
  busy.value = true;
  try {
    const { data } = await axios.post(base.value, {
      name: form.value.name.trim(),
    });
    wizard.value = {
      step: 2,
      name: data.name,
      os: form.value.os,
      code: data.code,
      id: data.id,
    };
    startCountdown(data.expires_in || 600);
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.message || t('RAGENT.HOSTS.ERROR'));
  } finally {
    busy.value = false;
  }
};

const renewCode = async () => {
  busy.value = true;
  try {
    const { data } = await axios.post(`${base.value}/${wizard.value.id}/pair`);
    wizard.value = { ...wizard.value, code: data.code };
    startCountdown(data.expires_in || 600);
  } catch (e) {
    useAlert(e?.response?.data?.message || t('RAGENT.HOSTS.ERROR'));
  } finally {
    busy.value = false;
  }
};

const reinstall = async host => {
  form.value = { name: host.name, os: host.os === 'linux' ? 'linux' : 'windows' };
  wizard.value = {
    step: 2,
    name: host.name,
    os: form.value.os,
    id: host.id,
    code: '',
  };
  await renewCode();
};

const test = async host => {
  try {
    const { data } = await axios.post(`${base.value}/${host.id}/test`);
    results.value = { ...results.value, [host.id]: data };
  } catch (e) {
    results.value = {
      ...results.value,
      [host.id]: { ok: false, detail: t('RAGENT.HOSTS.ERROR') },
    };
  }
};

const rename = async host => {
  // eslint-disable-next-line no-alert
  const name = window.prompt(t('RAGENT.HOSTS.RENAME'), host.name);
  if (!name || name === host.name) return;
  try {
    await axios.put(`${base.value}/${host.id}`, { name });
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.message || t('RAGENT.HOSTS.ERROR'));
  }
};

const remove = async host => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAGENT.HOSTS.CONFIRM_REMOVE', { name: host.name })))
    return;
  await axios.delete(`${base.value}/${host.id}`);
  await load();
};

const close = () => {
  wizard.value = null;
  clearInterval(tick);
  form.value = { name: '', os: 'windows' };
};

const mmss = computed(
  () =>
    `${String(Math.floor(countdown.value / 60)).padStart(2, '0')}:${String(countdown.value % 60).padStart(2, '0')}`
);
const linuxCmd = computed(
  () =>
    `curl -fsSL ${HUB}/dl/install.sh | sudo sh -s -- ${wizard.value?.code || ''}`
);
const winUrl = `${HUB}/dl/luar-conector-windows-amd64.exe`;
const osLabel = os => ({ windows: 'Windows', linux: 'Linux' })[os] || '—';
const copy = text => navigator.clipboard?.writeText(text);
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-n-weak p-4"
    data-testid="hosts-panel"
  >
    <header class="flex items-center gap-2">
      <h2 class="text-heading-2 text-n-slate-12">
        {{ t('RAGENT.HOSTS.TITLE') }}
      </h2>
      <Button
        class="ms-auto"
        size="sm"
        :label="t('RAGENT.HOSTS.ADD')"
        @click="wizard = { step: 1 }"
      />
    </header>
    <p class="text-body-main text-n-slate-11">{{ t('RAGENT.HOSTS.HELP') }}</p>

    <div v-if="wizard" class="flex flex-col gap-3 rounded-xl bg-n-alpha-2 p-4">
      <template v-if="wizard.step === 1">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('RAGENT.HOSTS.STEP1') }}
        </h3>
        <label class="text-body-main text-n-slate-11">
          {{ t('RAGENT.HOSTS.NAME') }}
          <input
            v-model="form.name"
            type="text"
            class="!mb-0 w-full max-w-sm"
            maxlength="60"
            :placeholder="t('RAGENT.HOSTS.NAME_PLACEHOLDER')"
          />
        </label>
        <div class="flex gap-2">
          <button
            v-for="o in ['windows', 'linux']"
            :key="o"
            type="button"
            class="rounded-xl border px-3 py-2 text-body-main"
            :class="
              form.os === o
                ? 'border-n-brand bg-n-alpha-2 text-n-slate-12'
                : 'border-n-weak text-n-slate-11'
            "
            @click="form.os = o"
          >
            {{ osLabel(o) }}
          </button>
        </div>
        <div class="flex gap-2">
          <Button
            :label="t('RAGENT.HOSTS.NEXT')"
            :disabled="busy || !form.name.trim()"
            @click="create"
          />
          <Button
            variant="ghost"
            color="slate"
            :label="t('RAGENT.HOSTS.CANCEL')"
            @click="close"
          />
        </div>
      </template>

      <template v-else-if="wizard.step === 2">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('RAGENT.HOSTS.STEP2', { name: wizard.name }) }}
        </h3>
        <template v-if="wizard.os === 'windows'">
          <p class="text-body-main text-n-slate-11">
            {{ t('RAGENT.HOSTS.WIN_STEPS') }}
          </p>
          <a
            :href="winUrl"
            class="w-fit rounded-full bg-n-brand px-4 py-2 text-white"
          >
            {{ t('RAGENT.HOSTS.DOWNLOAD') }}
          </a>
        </template>
        <template v-else>
          <p class="text-body-main text-n-slate-11">
            {{ t('RAGENT.HOSTS.LINUX_STEPS') }}
          </p>
          <code class="break-all rounded-lg bg-n-alpha-2 p-2 font-mono text-sm">
            {{ linuxCmd }}
          </code>
          <Button
            size="sm"
            variant="faded"
            :label="t('RAGENT.HOSTS.COPY')"
            @click="copy(linuxCmd)"
          />
        </template>
        <p class="text-body-main text-n-slate-11">
          {{ t('RAGENT.HOSTS.CODE') }}
        </p>
        <code class="text-heading-1 text-n-slate-12" data-testid="pair-code">
          {{ wizard.code }}
        </code>
        <p
          class="text-body-main"
          :class="countdown ? 'text-n-slate-11' : 'text-n-ruby-11'"
        >
          {{
            countdown
              ? t('RAGENT.HOSTS.EXPIRES', { time: mmss })
              : t('RAGENT.HOSTS.EXPIRED')
          }}
        </p>
        <div class="flex gap-2">
          <Button
            :label="t('RAGENT.HOSTS.INSTALLED')"
            @click="wizard = { ...wizard, step: 3 }"
          />
          <Button
            variant="faded"
            :disabled="busy"
            :label="t('RAGENT.HOSTS.NEW_CODE')"
            @click="renewCode"
          />
          <Button
            variant="ghost"
            color="slate"
            :label="t('RAGENT.HOSTS.CANCEL')"
            @click="close"
          />
        </div>
      </template>

      <template v-else-if="wizard.step === 3">
        <h3 class="text-heading-3 text-n-slate-12">
          {{ t('RAGENT.HOSTS.STEP3') }}
        </h3>
        <p class="text-body-main text-n-slate-11">
          {{ t('RAGENT.HOSTS.WAITING') }}
        </p>
        <div class="flex gap-2">
          <Button
            variant="faded"
            :label="t('RAGENT.HOSTS.BACK')"
            @click="wizard = { ...wizard, step: 2 }"
          />
          <Button
            variant="ghost"
            color="slate"
            :label="t('RAGENT.HOSTS.CANCEL')"
            @click="close"
          />
        </div>
      </template>

      <template v-else>
        <h3 class="text-heading-3 text-n-teal-11">
          {{ t('RAGENT.HOSTS.CONNECTED', { name: wizard.name }) }}
        </h3>
        <Button :label="t('RAGENT.HOSTS.DONE')" @click="close" />
      </template>
    </div>

    <p v-if="loading" class="text-n-slate-11">{{ t('RAGENT.CHAT.LOADING') }}</p>
    <p v-else-if="failed" class="text-n-ruby-11" role="alert">
      {{ t('RAGENT.HOSTS.LOAD_ERROR') }}
    </p>
    <p
      v-else-if="!hosts.length && !wizard"
      class="text-body-main text-n-slate-11"
    >
      {{ t('RAGENT.HOSTS.EMPTY') }}
    </p>
    <ul v-else class="divide-y divide-n-weak">
      <li
        v-for="h in hosts"
        :key="h.id"
        class="flex flex-wrap items-center gap-2 py-2"
      >
        <span class="min-w-0 flex-1">
          <span class="text-n-slate-12">{{ h.name }}</span>
          <span class="ms-2 text-sm text-n-slate-11">
            {{ osLabel(h.os) }}<template v-if="h.version"> · {{ h.version }}</template>
          </span>
        </span>
        <span
          class="rounded-full px-2 py-0.5 text-sm"
          :class="
            h.online
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-2 text-n-slate-11'
          "
          :data-testid="`host-state-${h.name}`"
        >
          {{
            !h.paired
              ? t('RAGENT.HOSTS.PENDING')
              : h.online
                ? t('RAGENT.HOSTS.ONLINE')
                : t('RAGENT.HOSTS.OFFLINE')
          }}
        </span>
        <Button
          size="sm"
          variant="faded"
          :label="t('RAGENT.HOSTS.TEST')"
          @click="test(h)"
        />
        <Button
          size="sm"
          variant="faded"
          :label="t('RAGENT.HOSTS.REINSTALL')"
          @click="reinstall(h)"
        />
        <Button
          size="sm"
          variant="faded"
          :label="t('RAGENT.HOSTS.RENAME_BTN')"
          @click="rename(h)"
        />
        <Button
          size="sm"
          color="ruby"
          :label="t('RAGENT.HOSTS.REMOVE')"
          @click="remove(h)"
        />
        <p
          v-if="results[h.id]"
          class="w-full text-sm"
          :class="results[h.id].ok ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          {{ results[h.id].detail }}
        </p>
      </li>
    </ul>
  </section>
</template>
