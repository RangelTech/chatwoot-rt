// Regras puras do quadro (testáveis sem montar componente).

// Âncora enviada ao soltar o cartão: o cartão que fica logo depois dele na coluna (vazio = fim).
export const beforeCardIdAfterDrop = (items, newIndex) => {
  const next = items[newIndex + 1];
  return next ? next.id : null;
};

// Reordenar etapa: `direction` -1 (esquerda) ou +1 (direita). Devolve o before_stage_id ('' = fim)
// ou null quando o movimento não existe (já está na ponta).
export const stageAnchor = (stages, id, direction) => {
  const index = stages.findIndex(s => s.id === id);
  const target = index + direction;
  if (index < 0 || target < 0 || target >= stages.length) return null;
  const anchor = direction < 0 ? stages[target] : stages[target + 1];
  return anchor ? anchor.id : '';
};

// Chave de i18n do toast para cada status de erro do movimento.
export const moveErrorKey = status =>
  ({
    409: 'ERROR_CONFLICT',
    422: 'ERROR_INVALID',
    403: 'ERROR_FORBIDDEN',
    404: 'ERROR_NOT_FOUND',
  })[status] || 'ERROR_GENERIC';
