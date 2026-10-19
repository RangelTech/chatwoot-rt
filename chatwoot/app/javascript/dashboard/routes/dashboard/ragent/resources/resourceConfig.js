// Cadastros de IA: cada tela é uma entrada aqui (colunas, formulário e permissões).
// O servidor só aceita as chaves listadas (allowlist em RtAi::ResourcesController).
export const RESOURCES = {
  providers: {
    title: 'PROVIDERS',
    manage: 'ai.providers.manage',
    columns: ['name', 'provider', 'model'],
    fields: [
      { key: 'name', label: 'NAME' },
      {
        key: 'provider',
        label: 'PROVIDER',
        options: ['openai', 'anthropic', 'google', 'openrouter', 'custom'],
      },
      { key: 'model', label: 'MODEL' },
      { key: 'api_key', label: 'API_KEY', secret: true },
      { key: 'api_base', label: 'API_BASE', optional: true },
    ],
  },
  credentials: {
    title: 'CREDENTIALS',
    manage: 'ai.credentials.manage',
    columns: ['name', 'is_active', 'updated_at'],
    fields: [
      { key: 'name', label: 'NAME' },
      { key: 'value', label: 'VALUE', secret: true },
    ],
  },
  sources: {
    title: 'SOURCES',
    manage: 'ai.knowledge.manage',
    columns: ['name', 'kind', 'status'],
    fields: [
      { key: 'name', label: 'NAME' },
      { key: 'kind', label: 'KIND', options: ['postgres', 'mysql', 'sqlserver', 'rest'] },
      { key: 'config', label: 'CONFIG_JSON', json: true },
      { key: 'secret', label: 'SECRET', secret: true, optional: true },
    ],
  },
  files: {
    title: 'FILES',
    manage: 'ai.knowledge.manage',
    columns: ['name', 'status', 'size_bytes'],
    fields: [],
  },
  memories: {
    title: 'MEMORIES',
    manage: 'ai.knowledge.manage',
    columns: ['content', 'created_at'],
    fields: [],
  },
  usage: { title: 'USAGE', columns: [], fields: [] },
  runs: {
    title: 'RUNS',
    columns: ['title', 'status', 'created_at'],
    fields: [],
  },
  environment: {
    title: 'ENVIRONMENT',
    manage: 'ai.environment.manage',
    columns: [],
    fields: [],
    actions: ['start', 'stop', 'backup'],
  },
  integrations: {
    title: 'INTEGRATIONS',
    manage: 'ai.integrations.manage',
    columns: ['name', 'status'],
    fields: [{ key: 'name', label: 'NAME' }],
  },
  payments: {
    title: 'PAYMENTS',
    manage: 'ai.payments.manage',
    columns: ['sandbox', 'has_token', 'is_active'],
    fields: [
      { key: 'access_token', label: 'ACCESS_TOKEN', secret: true },
      { key: 'webhook_secret', label: 'WEBHOOK_SECRET', secret: true, optional: true },
    ],
  },
};

export const ROUTES = [
  ['providers', 'ai.providers.view'],
  ['credentials', 'ai.credentials.view'],
  ['sources', 'ai.knowledge.view'],
  ['files', 'ai.knowledge.view'],
  ['memories', 'ai.knowledge.view'],
  ['usage', 'ai.usage.view'],
  ['runs', 'ai.runs.view'],
  ['environment', 'ai.environment.view'],
  ['integrations', 'ai.integrations.view'],
  ['payments', 'ai.payments.view'],
];
