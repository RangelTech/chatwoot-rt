<script setup>
import { onMounted, ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import rtAiMembers from 'dashboard/api/rtAiMembers';

const { t } = useI18n();
const members = ref([]);
const roles = ref([]);
const allowed = ref(false);

onMounted(async () => {
  try {
    const { data } = await rtAiMembers.get();
    members.value = data.members;
    roles.value = data.roles;
    allowed.value = true;
  } catch (error) {
    allowed.value = false;
  }
});

const changeRole = async (member, roleKey) => {
  try {
    const { data } = await rtAiMembers.update(member.id, { role_key: roleKey });
    member.ai_role_key = data.ai_role_key;
    useAlert(t('AGENT_MGMT.AI_ROLES.SAVED'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.AI_ROLES.ERROR'));
  }
};
</script>

<template>
  <section v-if="allowed" class="mt-8 border-t border-n-weak pt-6">
    <h3 class="text-heading-2 text-n-slate-12">
      {{ t('AGENT_MGMT.AI_ROLES.TITLE') }}
    </h3>
    <p class="mt-1 mb-4 text-body-main text-n-slate-11">
      {{ t('AGENT_MGMT.AI_ROLES.DESCRIPTION') }}
    </p>
    <div class="divide-y divide-n-weak border-t border-n-weak">
      <div
        v-for="member in members"
        :key="member.id"
        class="flex items-center justify-between gap-4 py-3"
      >
        <div class="min-w-0">
          <p class="truncate text-body-main text-n-slate-12">
            {{ member.name }}
          </p>
          <p class="truncate text-body-main text-n-slate-11">
            {{ member.email }}
          </p>
        </div>
        <select
          :value="member.ai_role_key"
          class="!mb-0 w-48"
          :aria-label="t('AGENT_MGMT.AI_ROLES.TITLE')"
          @change="changeRole(member, $event.target.value)"
        >
          <option v-for="role in roles" :key="role" :value="role">
            {{ t(`AGENT_MGMT.AI_ROLES.ROLES.${role.toUpperCase()}`) }}
          </option>
        </select>
      </div>
    </div>
  </section>
</template>
