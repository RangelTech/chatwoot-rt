// Destino inicial de uma Account (spec 10, U-2a): Chat com IA quando a Account tem a landing ligada,
// o binding ativo e a permissão; senão o dashboard de sempre. Falha ou lentidão => dashboard, sem loop.
const cache = new Map();
const TIMEOUT_MS = 2500;

export const ragentLandingPath = async accountId => {
  const key = String(accountId);
  if (cache.has(key)) return cache.get(key);
  let target = 'dashboard';
  try {
    const { data } = await window.axios.get(
      `/api/v1/accounts/${key}/rt_ai/me`,
      { timeout: TIMEOUT_MS }
    );
    const allowed =
      data?.flags?.chat_enabled &&
      data?.flags?.chat_landing_enabled &&
      (data.scopes || []).includes('ai.chat.view');
    if (allowed) target = 'ragent/chat';
  } catch (error) {
    target = 'dashboard';
  }
  cache.set(key, target);
  return target;
};

export const clearRagentLandingCache = () => cache.clear();
