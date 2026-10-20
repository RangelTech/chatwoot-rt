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
  usage: { title: 'USAGE', columns: [], fields: [] },
  runs: {
    title: 'RUNS',
    columns: ['started_at', 'agent', 'user', 'status', 'duration_ms'],
    paged: true,
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
    columns: ['name', 'key_prefix', 'is_active'],
    fields: [{ key: 'name', label: 'NAME' }],
  },
};

export const ROUTES = [
  ['providers', 'ai.providers.view'],
  ['usage', 'ai.usage.view'],
  ['runs', 'ai.runs.view'],
  ['environment', 'ai.environment.view'],
  ['integrations', 'ai.integrations.view'],
];
