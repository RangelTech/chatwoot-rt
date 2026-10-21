/* global axios */
import ApiClient from './ApiClient';

// BFF Rails do assistente "Conectar canal". O navegador nunca fala com o
// gateway. Senha e codigos 2FA so trafegam em step(); nao ha cache nem
// armazenamento: a resposta nunca contem credenciais.
class ChannelConnectionsAPI extends ApiClient {
  constructor() {
    super('channel_connections', { accountScoped: true });
  }

  catalog() {
    return axios.get(`${this.url}/catalog`);
  }

  start({ provider, consent, loginFlow }) {
    return axios.post(this.url, {
      provider,
      consent: consent === true,
      ...(loginFlow ? { login_flow: loginFlow } : {}),
    });
  }

  step(id, { stepId, kind, data }) {
    return axios.post(`${this.url}/${id}/step`, {
      step_id: stepId,
      kind,
      data,
    });
  }

  status(id) {
    return axios.get(`${this.url}/${id}`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  disconnect(id) {
    return axios.post(`${this.url}/${id}/disconnect`);
  }

  revoke(id) {
    return axios.post(`${this.url}/${id}/revoke`);
  }

  reauth(id) {
    return axios.post(`${this.url}/${id}/reauth`);
  }

  finalize(id, { name, teamId, agentBotId, syncSinceDays }) {
    return axios.post(`${this.url}/${id}/finalize`, {
      name,
      team_id: teamId || undefined,
      agent_bot_id: agentBotId || undefined,
      sync_since_days: syncSinceDays,
    });
  }

  // Contrato Fase F (F-contrato.md): fila de entrada da caixa. O canal nao
  // escolhe fila; so repassa a escolha do usuario.
  setEntryQueue({ inboxId, teamId }) {
    return axios.put(`${this.baseUrl()}/rt_ai/queues/entry`, {
      inbox_id: inboxId,
      routing_mode: 'filas',
      team_id: teamId,
    });
  }
}

export default new ChannelConnectionsAPI();
