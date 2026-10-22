<script setup>
import { ref, watch } from 'vue';
import api from 'dashboard/api/channelConnections';
import ConnectionPanel from './ConnectionPanel.vue';

// Carrega a conexao da caixa (inbox.connection_id) pelo BFF e mostra o painel.
const props = defineProps({
  inbox: { type: Object, required: true },
});

const connection = ref(null);

const load = async () => {
  const id = props.inbox.connection_id;
  if (!id) {
    connection.value = null;
    return;
  }
  try {
    const { data } = await api.status(id);
    connection.value = data.connection;
  } catch (e) {
    connection.value = null;
  }
};

watch(() => props.inbox.connection_id, load, { immediate: true });
</script>

<template>
  <ConnectionPanel
    v-if="connection"
    :inbox="inbox"
    :connection="connection"
    @changed="load"
  />
</template>
