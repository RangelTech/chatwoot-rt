<script setup>
import { useAttrs } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const attrs = useAttrs();
const globalConfig = useMapGetter('globalConfig/get');
</script>

<template>
  <img
    v-if="globalConfig.logoThumbnail"
    alt="Luar"
    v-bind="attrs"
    :src="globalConfig.logoThumbnail"
  />
  <svg
    v-else
    v-once
    v-bind="attrs"
    width="16"
    height="16"
    viewBox="0 0 100 100"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    aria-label="Luar"
    role="img"
  >
    <path
      fill="#75C8F2"
      fill-rule="evenodd"
      d="M50 0A50 50 0 1 1 50 100A50 50 0 1 1 50 0ZM12.63 34.56A41 41 0 0 1 65.44 87.37A38 38 0 0 0 12.63 34.56Z"
    />
  </svg>
</template>
