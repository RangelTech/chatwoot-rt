/* global axios */
import ApiClient from './ApiClient';

class RtAiChat extends ApiClient {
  constructor() {
    super('rt_ai/chats', { accountScoped: true });
  }

  templates() {
    return axios.get(`${this.url}/templates`);
  }

  messages(chatId) {
    return axios.get(`${this.url}/${chatId}/messages`);
  }

  streamTicket() {
    return axios.post(`${this.url}/stream_ticket`);
  }

  cancel(runId) {
    return axios.post(`${this.url}/${runId}/cancel`);
  }
}

export default new RtAiChat();
