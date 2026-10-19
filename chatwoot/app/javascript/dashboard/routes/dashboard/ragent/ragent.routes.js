import { frontendURL } from '../../../helper/URLHelper';
import ChatIndex from './chat/ChatIndex.vue';
import AgentsIndex from './agents/AgentsIndex.vue';
import SkillsIndex from './skills/SkillsIndex.vue';
import ResourcePage from './resources/ResourcePage.vue';
import InboxesPage from './inboxes/InboxesPage.vue';
import { ROUTES } from './resources/resourceConfig';

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
  {
    path: frontendURL('accounts/:accountId/ragent/skills'),
    name: 'ragent_skills',
    meta: { permissions: ['ai.skills.view'] },
    component: SkillsIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ragent/inboxes'),
    name: 'ragent_inboxes',
    meta: { permissions: ['ai.inbox_routing.view'] },
    component: InboxesPage,
  },
  ...ROUTES.map(([key, permission]) => ({
    path: frontendURL(`accounts/:accountId/ragent/${key}`),
    name: `ragent_${key}`,
    meta: { permissions: [permission], resource: key },
    component: ResourcePage,
  })),
];
