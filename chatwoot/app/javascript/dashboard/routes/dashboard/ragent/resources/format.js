// Formatação pt-BR das telas de cadastros (Uso, Ambiente, Execuções): nunca mostrar ISO, float
// cru nem JSON ao cliente. O custo do motor vem em dólar; a conversão para R$ é uma ESTIMATIVA.
const LOCALE = 'pt-BR';

// Cotação fixa só para dar ordem de grandeza; a tela sempre marca o valor como estimado.
export const USD_BRL_ESTIMATE = 5.5;

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

export const isDateKey = key => /(_at|_date)$/.test(key) || key === 'day';

export const formatDate = value => {
  if (!value) return '—';
  // "2026-10-19" sem hora: interpretar como data local, senão o fuso recua um dia.
  const dateOnly = DATE_ONLY.test(value);
  const date = dateOnly ? new Date(`${value}T12:00:00`) : new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return dateOnly
    ? date.toLocaleDateString(LOCALE)
    : date.toLocaleString(LOCALE, { dateStyle: 'short', timeStyle: 'short' });
};

export const formatNumber = (value, digits = 0) => {
  const number = Number(value);
  if (value === null || value === undefined || Number.isNaN(number)) return '—';
  return number.toLocaleString(LOCALE, {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
};

export const formatBytes = value => {
  const number = Number(value);
  if (value === null || value === undefined || Number.isNaN(number)) return '—';
  if (number < 1024) return `${formatNumber(number)} B`;
  if (number < 1024 * 1024) return `${formatNumber(number / 1024, 1)} KB`;
  return `${formatNumber(number / (1024 * 1024), 1)} MB`;
};

export const formatBRL = usd => {
  const number = Number(usd);
  if (usd === null || usd === undefined || Number.isNaN(number)) return '—';
  return (number * USD_BRL_ESTIMATE).toLocaleString(LOCALE, {
    style: 'currency',
    currency: 'BRL',
  });
};

export const formatDuration = ms => {
  const number = Number(ms);
  if (ms === null || ms === undefined || Number.isNaN(number)) return '—';
  return number >= 1000
    ? `${formatNumber(number / 1000, 1)} s`
    : `${formatNumber(number)} ms`;
};

export const percent = (used, limit) => {
  const u = Number(used);
  const l = Number(limit);
  if (!l || Number.isNaN(u) || Number.isNaN(l)) return null;
  return Math.min(100, Math.round((u / l) * 100));
};
