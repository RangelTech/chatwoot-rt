/* global axios */
import ApiClient from './ApiClient';

class RtAiAgents extends ApiClient {
  constructor() {
    super('rt_ai/agents', { accountScoped: true });
  }

  draft(id) {
    return axios.get(`${this.url}/${id}/draft`);
  }

  saveDraft(id, payload) {
    return axios.put(`${this.url}/${id}/update_draft`, payload);
  }

  validate(id, payload) {
    return axios.post(`${this.url}/${id}/validate`, payload);
  }

  createVersion(id, notes = '') {
    return axios.post(`${this.url}/${id}/create_version`, { notes });
  }

  publish(id, versionId) {
    return axios.post(`${this.url}/${id}/publish`, { version_id: versionId });
  }

  archive(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new RtAiAgents();
