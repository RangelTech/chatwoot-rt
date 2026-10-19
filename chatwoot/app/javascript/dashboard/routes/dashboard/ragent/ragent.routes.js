import { frontendURL } from '../../../helper/URLHelper';
import ChatIndex from './chat/ChatIndex.vue';
import AgentsIndex from './agents/AgentsIndex.vue';

const meta = { permissions: ['ai.chat.view'] };

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ragent/chat'),
    name: 'ragent_chat',
    meta,
    component: ChatIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ragent/chat/:chatId'),
    name: 'ragent_chat_detail',
    meta,
    component: ChatIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ragent/agents'),
    name: 'ragent_agents',
    meta: { permissions: ['ai.agents.view'] },
    component: AgentsIndex,
  },
];
