import { frontendURL } from '../../../helper/URLHelper';
import ChatIndex from './chat/ChatIndex.vue';
import AgentsIndex from './agents/AgentsIndex.vue';
import SkillsIndex from './skills/SkillsIndex.vue';
import ResourcePage from './resources/ResourcePage.vue';
import InboxesPage from './inboxes/InboxesPage.vue';
import CredentialsPage from './credentials/CredentialsPage.vue';
import { ROUTES } from './resources/resourceConfig';

const meta = { permissions: ['ai.chat.view'] };

// A URL pública não carrega o nome técnico antigo; os endereços `/ragent/*` seguem valendo (redirecionam).
export const legacyRedirects = [
  {
    path: frontendURL('accounts/:accountId/ragent/:rest(.*)*'),
    redirect: to => ({
      path: to.path.replace('/ragent/', '/ia/'),
      query: to.query,
      hash: to.hash,
    }),
  },
  ...legacyRedirects,
];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ia/chat'),
    name: 'ragent_chat',
    meta,
    component: ChatIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ia/chat/:chatId'),
    name: 'ragent_chat_detail',
    meta,
    component: ChatIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ia/agents'),
    name: 'ragent_agents',
    meta: { permissions: ['ai.agents.view'] },
    component: AgentsIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ia/skills'),
    name: 'ragent_skills',
    meta: { permissions: ['ai.skills.view'] },
    component: SkillsIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ia/inboxes'),
    name: 'ragent_inboxes',
    meta: { permissions: ['ai.inbox_routing.view'] },
    component: InboxesPage,
  },
  {
    path: frontendURL('accounts/:accountId/ia/credentials'),
    name: 'ragent_credentials',
    meta: { permissions: ['ai.credentials.view'] },
    component: CredentialsPage,
  },
  ...ROUTES.map(([key, permission]) => ({
    path: frontendURL(`accounts/:accountId/ia/${key}`),
    name: `ragent_${key}`,
    meta: { permissions: [permission], resource: key },
    component: ResourcePage,
  })),
  ...legacyRedirects,
];
