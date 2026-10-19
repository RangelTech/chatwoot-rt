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

  // Arquivo de qualquer tipo para a pasta arquivos/ do pacote. Com `path`, substitui aquele arquivo.
  uploadFile(id, file, path = null) {
    const form = new FormData();
    form.append('file', file);
    if (path) form.append('path', path);
    return axios.post(`${this.url}/${id}/upload_file`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  deleteFile(id, path) {
    return axios.delete(`${this.url}/${id}/delete_file`, { params: { path } });
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
