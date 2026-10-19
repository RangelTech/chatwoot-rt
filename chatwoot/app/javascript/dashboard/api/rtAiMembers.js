import ApiClient from './ApiClient';

class RtAiMembers extends ApiClient {
  constructor() {
    super('rt_ai/members', { accountScoped: true });
  }
}

export default new RtAiMembers();
