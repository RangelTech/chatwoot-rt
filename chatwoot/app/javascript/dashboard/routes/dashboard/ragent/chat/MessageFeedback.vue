<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import rtAiChat from 'dashboard/api/rtAiChat';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  chatId: { type: String, required: true },
  messageId: { type: String, required: true },
});

const { t } = useI18n();

const rating = ref(0);
const comment = ref('');
const askComment = ref(false);
const sent = ref(false);
const failed = ref(false);
const busy = ref(false);

const submit = async () => {
  busy.value = true;
  failed.value = false;
  try {
    await rtAiChat.feedback(props.chatId, {
      messageId: props.messageId,
      rating: rating.value,
      comment: comment.value.trim(),
    });
    sent.value = true;
    askComment.value = false;
  } catch (error) {
    failed.value = true;
  } finally {
    busy.value = false;
  }
};

const choose = value => {
  if (busy.value) return;
  rating.value = value;
  sent.value = false;
  askComment.value = true;
  // o voto vale já no clique; o comentário é opcional e reenvia a mesma avaliação
  submit().then(() => {
    askComment.value = true;
  });
};
</script>

<template>
  <div class="mt-1 flex flex-col gap-1" data-testid="message-feedback">
    <div class="flex items-center gap-1">
      <Button
        icon="i-lucide-thumbs-up"
        size="xs"
        variant="ghost"
        :color="rating === 1 ? 'teal' : 'slate'"
        :title="t('RAGENT.CHAT.FEEDBACK.GOOD')"
        :aria-label="t('RAGENT.CHAT.FEEDBACK.GOOD')"
        :aria-pressed="rating === 1"
        :disabled="busy"
        @click="choose(1)"
      />
      <Button
        icon="i-lucide-thumbs-down"
        size="xs"
        variant="ghost"
        :color="rating === -1 ? 'ruby' : 'slate'"
        :title="t('RAGENT.CHAT.FEEDBACK.BAD')"
        :aria-label="t('RAGENT.CHAT.FEEDBACK.BAD')"
        :aria-pressed="rating === -1"
        :disabled="busy"
        @click="choose(-1)"
      />
      <span v-if="sent" class="text-body-main text-n-slate-11">
        {{ t('RAGENT.CHAT.FEEDBACK.THANKS') }}
      </span>
      <span v-if="failed" class="text-body-main text-n-ruby-11" role="alert">
        {{ t('RAGENT.CHAT.FEEDBACK.ERROR') }}
      </span>
    </div>
    <form
      v-if="askComment && rating"
      class="flex max-w-md items-end gap-2"
      @submit.prevent="submit"
    >
      <input
        v-model="comment"
        type="text"
        maxlength="2000"
        class="!mb-0 flex-1"
        :placeholder="t('RAGENT.CHAT.FEEDBACK.COMMENT')"
        :aria-label="t('RAGENT.CHAT.FEEDBACK.COMMENT')"
      />
      <Button
        :label="t('RAGENT.CHAT.FEEDBACK.SEND')"
        size="sm"
        type="submit"
        :disabled="busy"
      />
    </form>
  </div>
</template>
