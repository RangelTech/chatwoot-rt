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

  feedback(chatId, { messageId, rating, comment = '' }) {
    return axios.post(`${this.url}/${chatId}/feedback`, {
      message_id: messageId,
      rating,
      comment,
    });
  }

  artifacts(chatId) {
    return axios.get(`${this.url}/${chatId}/artifacts`);
  }

  // Baixa pelo BFF (autenticado); `inline` só vale para imagem. Devolve o blob.
  artifactFile(chatId, artifactId, { inline = false } = {}) {
    return axios.get(`${this.url}/${chatId}/artifacts/${artifactId}/download`, {
      responseType: 'blob',
      params: inline ? { inline: 1 } : {},
    });
  }

  pendingApprovals() {
    return axios.get(this.url.replace('/chats', '/approvals'));
  }

  decideApproval(approvalId, decision) {
    return axios.post(
      `${this.url.replace('/chats', '/approvals')}/${approvalId}/decide`,
      { decision }
    );
  }
}

export default new RtAiChat();
