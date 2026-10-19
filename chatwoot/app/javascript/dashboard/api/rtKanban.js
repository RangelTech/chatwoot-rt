/* global axios */

import ApiClient from './ApiClient';

class RtKanbanAPI extends ApiClient {
  constructor() {
    super('rt_kanban', { accountScoped: true });
  }

  getBoard() {
    return axios.get(`${this.url}/board`);
  }

  setEnabled(enabled) {
    return axios.patch(`${this.url}/board`, { enabled });
  }

  getCards(params) {
    return axios.get(`${this.url}/cards`, { params });
  }

  moveCard(cardId, payload) {
    return axios.patch(`${this.url}/cards/${cardId}/move`, payload);
  }

  createStage(payload) {
    return axios.post(`${this.url}/stages`, payload);
  }

  updateStage(stageId, payload) {
    return axios.patch(`${this.url}/stages/${stageId}`, payload);
  }
}

export default new RtKanbanAPI();
