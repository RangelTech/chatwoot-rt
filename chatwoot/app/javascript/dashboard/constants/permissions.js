export const AVAILABLE_CUSTOM_ROLE_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
  'contact_manage',
  'report_manage',
  'knowledge_base_manage',
];

export const ROLES = ['agent', 'administrator'];

export const CONVERSATION_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const MANAGE_ALL_CONVERSATION_PERMISSIONS = 'conversation_manage';

export const CONVERSATION_UNASSIGNED_PERMISSIONS =
  'conversation_unassigned_manage';

export const CONVERSATION_PARTICIPATING_PERMISSIONS =
  'conversation_participating_manage';

export const CONTACT_PERMISSIONS = 'contact_manage';

export const REPORTS_PERMISSIONS = 'report_manage';

export const PORTAL_PERMISSIONS = 'knowledge_base_manage';

export const ASSIGNEE_TYPE_TAB_PERMISSIONS = {
  me: {
    count: 'mineCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  unassigned: {
    count: 'unAssignedCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  all: {
    count: 'allCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
    ],
  },
};

// Permissões de IA (spec 10): somam-se a ROLES; o back as devolve em `permissions`.
export const AI_PERMISSIONS = {
  CHAT_VIEW: 'ai.chat.view',
  CHAT_RUN: 'ai.chat.run',
  AGENTS_VIEW: 'ai.agents.view',
  AGENTS_EDIT: 'ai.agents.edit',
  SKILLS_VIEW: 'ai.skills.view',
  RUNS_VIEW: 'ai.runs.view',
  USAGE_VIEW: 'ai.usage.view',
  PROVIDERS_VIEW: 'ai.providers.view',
  CREDENTIALS_VIEW: 'ai.credentials.view',
  ENVIRONMENT_VIEW: 'ai.environment.view',
  INBOX_ROUTING_VIEW: 'ai.inbox_routing.view',
  MEMBERS_MANAGE_ROLES: 'ai.members.manage_roles',
};
