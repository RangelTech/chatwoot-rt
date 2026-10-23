import { frontendURL } from '../../../helper/URLHelper';
import ChatIndex from './chat/ChatIndex.vue';
import AgentsIndex from './agents/AgentsIndex.vue';
import SkillsIndex from './skills/SkillsIndex.vue';
import ResourcePage from './resources/ResourcePage.vue';
import InboxesPage from './inboxes/InboxesPage.vue';
import CredentialsPage from './credentials/CredentialsPage.vue';
import { ROUTES } from './resources/resourceConfig';

const meta = { permissions: ['ai.chat.view'] };

const settingsPath = key => frontendURL(`accounts/:accountId/settings/ai/${key}`);

// As páginas de uso ficam no menu principal. Cadastros ficam em Configurações
// -> Inteligência artificial. A separação evita que a tela diária vire um
// painel administrativo com abas.
const settingsRoutes = [
  ['agents', 'ai.agents.view', AgentsIndex],
  ['skills', 'ai.skills.view', SkillsIndex],
  ['routines', 'ai.skills.view', SkillsIndex],
  ['queues', 'ai.inbox_routing.view', InboxesPage],
  ['credentials', 'ai.credentials.view', CredentialsPage],
  ['providers', 'ai.providers.view', ResourcePage],
  ['combos', 'ai.providers.view', ResourcePage],
  ['integrations', 'ai.integrations.view', ResourcePage],
  ['quotas', 'ai.usage.view', ResourcePage],
  ['requests', 'ai.usage.view', ResourcePage],
];

const legacySettingsPaths = {
  agents: 'agents',
  skills: 'skills',
  routines: 'routines',
  providers: 'providers',
  combos: 'combos',
  credentials: 'credentials',
  inboxes: 'queues',
  integrations: 'integrations',
  quotas: 'quotas',
  requests: 'requests',
};

// Endereços antigos permanecem úteis em favoritos e em links enviados antes
// da Spec 12, mas sempre levam para a arquitetura nova.
const legacyAiRedirects = Object.entries(legacySettingsPaths).map(([from, to]) => ({
  path: frontendURL(`accounts/:accountId/ia/${from}`),
  redirect: route => ({
    path: route.path.replace(`/ia/${from}`, `/settings/ai/${to}`),
    query: route.query,
    hash: route.hash,
  }),
}));

export const legacyRedirects = [
  ...legacyAiRedirects,
  {
    path: frontendURL('accounts/:accountId/ragent/:rest(.*)*'),
    redirect: to => ({
      path: to.path.replace('/ragent/', '/ia/'),
      query: to.query,
      hash: to.hash,
    }),
  },
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
    path: frontendURL('accounts/:accountId/ia/usage'),
    name: 'ragent_usage',
    meta: { permissions: ['ai.usage.view'], resource: 'usage' },
    component: ResourcePage,
  },
  {
    path: frontendURL('accounts/:accountId/ia/environment'),
    name: 'ragent_environment',
    meta: { permissions: ['ai.environment.view'], resource: 'environment' },
    component: ResourcePage,
  },
  {
    path: frontendURL('accounts/:accountId/ia/runs'),
    name: 'ragent_runs',
    meta: { permissions: ['ai.runs.view'], resource: 'runs' },
    component: ResourcePage,
  },
  ...settingsRoutes.map(([key, permission, component]) => ({
    path: settingsPath(key),
    name: `ragent_${key}`,
    meta: { permissions: [permission], resource: ['providers', 'combos', 'integrations', 'quotas', 'requests'].includes(key) ? key : undefined },
    component,
  })),
  ...ROUTES.filter(([key]) => !['usage', 'environment', 'runs', 'providers', 'combos', 'integrations', 'quotas', 'requests'].includes(key)).map(([key, permission]) => ({
    path: frontendURL(`accounts/:accountId/ia/${key}`),
    name: `ragent_${key}`,
    meta: { permissions: [permission], resource: key },
    component: ResourcePage,
  })),
  ...legacyRedirects,
];
