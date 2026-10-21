<script setup>
import { ref, computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { SYNC_WINDOWS_DAYS } from './constants';

const props = defineProps({
  defaultName: { type: String, default: '' },
  busy: { type: Boolean, default: false },
});
const emit = defineEmits(['submit']);

const teams = useMapGetter('teams/getTeams');
const agentBots = useMapGetter('agentBots/getBots');

const name = ref(props.defaultName);
const teamId = ref('');
const agentBotId = ref('');
const syncSinceDays = ref(SYNC_WINDOWS_DAYS[SYNC_WINDOWS_DAYS.length - 1]);

const canSubmit = computed(() => !props.busy && name.value.trim().length > 0);

const onSubmit = () => {
  if (!canSubmit.value) return;
  emit('submit', {
    name: name.value.trim(),
    teamId: teamId.value ? Number(teamId.value) : null,
    agentBotId: agentBotId.value ? Number(agentBotId.value) : null,
    syncSinceDays: Number(syncSinceDays.value),
  });
};
</script>

<template>
  <form
    class="flex flex-col gap-5"
    data-test="finalize-step"
    @submit.prevent="onSubmit"
  >
    <p class="m-0 text-sm text-n-slate-11">
      {{ $t('CHANNEL_CONNECT.FINALIZE.HELP') }}
    </p>
    <label class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12">
      {{ $t('CHANNEL_CONNECT.FINALIZE.NAME') }}
      <input v-model="name" type="text" class="!mb-0" data-field="name" />
    </label>
    <label class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12">
      {{ $t('CHANNEL_CONNECT.FINALIZE.TEAM') }}
      <select v-model="teamId" class="!mb-0" data-field="team">
        <option value="">{{ $t('CHANNEL_CONNECT.FINALIZE.NONE') }}</option>
        <option v-for="team in teams" :key="team.id" :value="team.id">
          {{ team.name }}
        </option>
      </select>
      <span class="text-xs font-normal text-n-slate-10">
        {{ $t('CHANNEL_CONNECT.FINALIZE.TEAM_HINT') }}
      </span>
    </label>
    <label class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12">
      {{ $t('CHANNEL_CONNECT.FINALIZE.AGENT') }}
      <select v-model="agentBotId" class="!mb-0" data-field="agent">
        <option value="">{{ $t('CHANNEL_CONNECT.FINALIZE.NONE') }}</option>
        <option v-for="bot in agentBots" :key="bot.id" :value="bot.id">
          {{ bot.name }}
        </option>
      </select>
    </label>
    <label class="flex flex-col gap-1.5 text-sm font-medium text-n-slate-12">
      {{ $t('CHANNEL_CONNECT.FINALIZE.SYNC_WINDOW') }}
      <select v-model="syncSinceDays" class="!mb-0" data-field="sync">
        <option v-for="d in SYNC_WINDOWS_DAYS" :key="d" :value="d">
          {{ $t('CHANNEL_CONNECT.FINALIZE.DAYS', { count: d }) }}
        </option>
      </select>
    </label>
    <div>
      <NextButton
        type="submit"
        blue
        :is-loading="busy"
        :disabled="!canSubmit"
        :label="$t('CHANNEL_CONNECT.FINALIZE.SUBMIT')"
      />
    </div>
  </form>
</template>
