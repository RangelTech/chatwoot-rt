import rtAiChat from 'dashboard/api/rtAiChat';

// Lê o stream SSE (POST, mesma origem) e entrega cada evento ao chamador.
export async function streamChat({ message, chatId, templateId, signal, onEvent }) {
  const { data } = await rtAiChat.streamTicket();
  const response = await fetch('/ai/stream/chat/send', {
    method: 'POST',
    signal,
    headers: {
      'Content-Type': 'application/json',
      'X-UI-Context': data.ticket,
    },
    body: JSON.stringify({
      message,
      chat_id: chatId || null,
      template_id: templateId || null,
    }),
  });
  if (!response.ok || !response.body) {
    let detail = 'Não foi possível enviar a mensagem.';
    try {
      detail = (await response.json()).detail || detail;
    } catch (error) {
      // corpo sem JSON: mantém a mensagem padrão
    }
    onEvent('error', { detail });
    return;
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let done = false;
  while (!done) {
    // eslint-disable-next-line no-await-in-loop
    const chunk = await reader.read();
    done = chunk.done;
    buffer += decoder.decode(chunk.value || new Uint8Array(), { stream: !done });
    const blocks = buffer.split('\n\n');
    buffer = blocks.pop();
    blocks.forEach(block => {
      let event = 'message';
      let payload = '';
      block.split('\n').forEach(line => {
        if (line.startsWith('event:')) event = line.slice(6).trim();
        if (line.startsWith('data:')) payload += line.slice(5).trim();
      });
      if (!payload) return;
      try {
        onEvent(event, JSON.parse(payload));
      } catch (error) {
        // evento malformado: ignora
      }
    });
  }
}
