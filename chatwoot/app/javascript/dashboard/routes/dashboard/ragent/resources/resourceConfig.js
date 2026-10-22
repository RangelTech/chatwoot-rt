// Cadastros de IA: cada tela é uma entrada aqui (colunas, formulário e permissões).
// O servidor só aceita as chaves listadas (allowlist em RtAi::ResourcesController).
export const RESOURCES = {
  providers: {
    title: 'PROVIDERS',
    manage: 'ai.providers.manage',
    itemActions: ['test'],
    itemReads: ['models'],
    columns: ['name', 'provider', 'model', 'is_active'],
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
  combos: {
    title: 'COMBOS',
    manage: 'ai.providers.manage',
    columns: ['name', 'models'],
    // O Gateway recebe uma lista ordenada de modelos; mantemos o JSON no campo
    // para não transformar uma lista em texto no BFF.
    fields: [
      { key: 'name', label: 'NAME' },
      { key: 'models', label: 'MODELS', json: true, placeholder: '["gpt-4o-mini"]' },
    ],
  },
  quotas: { title: 'QUOTAS', columns: [], fields: [] },
  usage: { title: 'USAGE', columns: [], fields: [] },
  requests: {
    title: 'REQUESTS',
    columns: ['timestamp', 'provider', 'model', 'requestedModel', 'endpoint', 'status', 'cost'],
    fields: [],
  },
  runs: {
    title: 'RUNS',
    columns: ['agent', 'user', 'status', 'started_at', 'duration_ms'],
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
  ['combos', 'ai.providers.view'],
  ['quotas', 'ai.usage.view'],
  ['usage', 'ai.usage.view'],
  ['requests', 'ai.usage.view'],
  ['runs', 'ai.runs.view'],
  ['environment', 'ai.environment.view'],
  ['integrations', 'ai.integrations.view'],
];
