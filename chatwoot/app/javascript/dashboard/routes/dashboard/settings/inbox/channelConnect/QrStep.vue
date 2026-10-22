<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import QRCode from 'qrcode';
import NextButton from 'dashboard/components-next/button/Button.vue';

// Passo "qr" e "pairing_code". O QR e renderizado no cliente a partir de
// qr.data; a renovacao e feita pelo composable (polling) e chega aqui como
// novo step.qr.data -- este componente so redesenha e conta o tempo.
const props = defineProps({
  step: { type: Object, required: true },
  provider: { type: String, required: true },
});
const emit = defineEmits(['cancel']);

const dataUrl = ref('');
const secondsLeft = ref(null);
let ticker = null;

const isPairing = computed(() => props.step.kind === 'pairing_code');

const draw = async () => {
  const data = props.step.qr?.data;
  if (!data) {
    dataUrl.value = '';
    return;
  }
  try {
    dataUrl.value = await QRCode.toDataURL(data, {
      margin: 1,
      width: 256,
      errorCorrectionLevel: 'M',
    });
  } catch (e) {
    dataUrl.value = '';
  }
};

// Relogio do servidor e do navegador podem diferir (visto em producao: 9 min).
// A contagem usa o tempo RELATIVO (refresh_after_s no momento em que o QR chegou).
let shownAt = Date.now();
let baseline = null;
const markNew = () => {
  shownAt = Date.now();
  baseline = props.step.qr?.refresh_after_s ?? null;
};
const tick = () => {
  const qr = props.step.qr;
  if (!qr) {
    secondsLeft.value = null;
    return;
  }
  if (baseline !== null) {
    secondsLeft.value = Math.max(
      0,
      Math.ceil(baseline - (Date.now() - shownAt) / 1000)
    );
    return;
  }
  secondsLeft.value = qr.expires_at
    ? Math.max(0, Math.ceil((Date.parse(qr.expires_at) - Date.now()) / 1000))
    : null;
};

watch(
  () => props.step.qr?.data,
  () => {
    markNew();
    draw();
    tick();
  }
);

onMounted(() => {
  markNew();
  draw();
  tick();
  ticker = setInterval(tick, 1000);
});
onBeforeUnmount(() => clearInterval(ticker));

const instructionKey = computed(() => {
  if (isPairing.value) return 'CHANNEL_CONNECT.STEPS.PAIRING_HELP';
  return `CHANNEL_CONNECT.STEPS.QR_HELP_${props.provider.toUpperCase()}`;
});
const expired = computed(() => secondsLeft.value === 0);
</script>

<template>
  <div class="flex flex-col items-center gap-4 text-center" data-test="qr-step">
    <template v-if="!isPairing">
      <div
        class="relative rounded-2xl border border-solid border-n-weak bg-white p-3 shadow-sm"
      >
        <img
          v-if="dataUrl"
          :src="dataUrl"
          :alt="$t('CHANNEL_CONNECT.STEPS.QR_ALT')"
          class="size-56 max-w-full sm:size-64"
          data-test="qr-image"
        />
        <div v-else class="size-56 animate-pulse rounded-lg bg-n-alpha-2" />
        <div
          v-if="expired"
          class="absolute inset-0 flex items-center justify-center rounded-2xl bg-white/90 text-sm font-medium text-slate-800"
        >
          {{ $t('CHANNEL_CONNECT.STEPS.QR_REFRESHING') }}
        </div>
      </div>
      <p
        v-if="secondsLeft !== null"
        class="m-0 text-xs text-n-slate-10"
        data-test="qr-countdown"
      >
        {{
          $t('CHANNEL_CONNECT.STEPS.QR_EXPIRES_IN', { seconds: secondsLeft })
        }}
      </p>
    </template>
    <div
      v-else
      class="rounded-2xl border border-solid border-n-weak bg-n-solid-2 px-6 py-5"
    >
      <p
        class="m-0 font-mono text-3xl font-semibold tracking-[0.3em] text-n-slate-12"
        data-test="pairing-code"
      >
        {{ step.pairing_code }}
      </p>
    </div>
    <p class="m-0 max-w-sm text-sm text-n-slate-11">
      {{ $t(instructionKey) }}
    </p>
    <NextButton
      variant="ghost"
      color="slate"
      :label="$t('CHANNEL_CONNECT.ACTIONS.CANCEL')"
      @click="emit('cancel')"
    />
  </div>
</template>
