import { ERROR_CODES } from './constants';

// error_code do gateway -> chave i18n em portugues claro. Codigo desconhecido
// cai em "generic" (nunca mostra o codigo cru nem mensagem do provedor).
export const errorI18nKey = code =>
  ERROR_CODES.includes(code)
    ? `CHANNEL_CONNECT.ERRORS.${code.toUpperCase()}`
    : 'CHANNEL_CONNECT.ERRORS.GENERIC';

// Erros que nao permitem tentar de novo no mesmo passo.
export const isTerminalError = code =>
  ['too_many_attempts', 'account_locked', 'unsupported_step'].includes(code);

// Extrai {code, attemptsLeft} de uma resposta HTTP de erro do BFF.
export const parseHttpError = error => {
  const data = error?.response?.data || {};
  const nested = data.step || {};
  return {
    code:
      data.error_code ||
      nested.error_code ||
      (error?.response?.status === 429 ? 'too_many_attempts' : null) ||
      'provider_unavailable',
    attemptsLeft: data.attempts_left ?? nested.attempts_left ?? null,
  };
};
