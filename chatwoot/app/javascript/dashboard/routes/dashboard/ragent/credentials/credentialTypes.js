// Tipos da tela Credenciais: cada tipo tem seu formulário. O servidor só aceita estes campos
// (allowlist em RtAi::CredentialsController). Campos `secret` são write-only: nunca voltam do servidor,
// e em branco, ao substituir, significam "manter o valor atual".

const text = (key, extra = {}) => ({ key, kind: 'text', ...extra });
const secret = (key, extra = {}) => ({
  key,
  kind: 'password',
  secret: true,
  ...extra,
});

export const DB_KINDS = ['postgres', 'mysql', 'mongo', 'sqlite'];
export const DB_PORTS = { postgres: '5432', mysql: '3306', mongo: '27017' };

export const CREDENTIAL_TYPES = [
  {
    key: 'secret',
    fields: [
      text('name', { placeholder: 'MERCADO_PAGO_TOKEN' }),
      secret('value'),
    ],
  },
  {
    key: 'database',
    fields: [
      {
        key: 'db_kind',
        kind: 'select',
        options: DB_KINDS,
        default: 'postgres',
      },
      text('name', { placeholder: 'loja' }),
      text('host', { hideFor: ['sqlite'] }),
      {
        key: 'port',
        kind: 'number',
        hideFor: ['sqlite'],
        default: '5432',
        optional: true,
      },
      text('database', { hideFor: ['sqlite'] }),
      text('path', { onlyFor: ['sqlite'] }),
      text('user', { hideFor: ['sqlite'], optional: true }),
      secret('password', { hideFor: ['sqlite'], optional: true }),
      { key: 'ssl', kind: 'checkbox', hideFor: ['sqlite'], default: false },
    ],
  },
  {
    key: 'ssh',
    fields: [
      text('name', { placeholder: 'DO_SERVIDOR' }),
      text('host'),
      { key: 'port', kind: 'number', default: '22' },
      text('user'),
      {
        key: 'value',
        kind: 'textarea',
        secret: true,
        placeholder: '-----BEGIN OPENSSH PRIVATE KEY-----',
      },
    ],
  },
  {
    key: 'gcp',
    fields: [
      text('name', { default: 'SA' }),
      { key: 'value', kind: 'json-file', secret: true },
    ],
  },
  {
    key: 'email',
    fields: [
      text('label'),
      text('email_address'),
      text('smtp_host'),
      { key: 'smtp_port', kind: 'number', default: '587' },
      text('imap_host'),
      { key: 'imap_port', kind: 'number', default: '993' },
      text('username'),
      secret('password'),
      { key: 'use_tls', kind: 'checkbox', default: true },
    ],
  },
  {
    key: 'payment',
    fields: [
      secret('access_token'),
      secret('webhook_secret', { optional: true }),
      { key: 'sandbox', kind: 'checkbox', default: true },
    ],
  },
  { key: 'google', oauth: true, fields: [text('name', { optional: true })] },
  { key: 'microsoft', oauth: true, fields: [text('name', { optional: true })] },
];

export const typeOf = key => CREDENTIAL_TYPES.find(t => t.key === key);

// Campos visíveis para o estado atual do formulário (ex.: SQLite só pede o caminho do arquivo).
export const visibleFields = (type, form) =>
  (type?.fields || []).filter(f => {
    const kind = form.db_kind;
    if (f.hideFor && f.hideFor.includes(kind)) return false;
    if (f.onlyFor && !f.onlyFor.includes(kind)) return false;
    return true;
  });

// Valores iniciais: padrões do tipo e, ao substituir, os dados NÃO sensíveis do item (host, usuário...).
export const initialForm = (type, item = null) => {
  const form = {};
  (type?.fields || []).forEach(f => {
    if (f.secret) form[f.key] = '';
    else if (
      item &&
      item.info &&
      item.info[f.key] !== undefined &&
      item.info[f.key] !== null
    ) {
      form[f.key] = item.info[f.key];
    } else if (item && f.key === 'name') form[f.key] = item.name;
    else if (item && f.key === 'label') form[f.key] = item.name;
    else form[f.key] = f.default !== undefined ? f.default : '';
  });
  if (item && type?.key === 'database' && item.info?.db_kind)
    form.db_kind = item.info.db_kind;
  return form;
};

// Corpo enviado ao BFF: só campos visíveis e preenchidos. Ao substituir, nome e tipo de banco não mudam.
export const buildPayload = (type, form, { replace = false } = {}) => {
  const body = replace ? {} : { type: type.key };
  visibleFields(type, form).forEach(f => {
    if (replace && (f.key === 'name' || f.key === 'db_kind')) return;
    const value = form[f.key];
    if (f.kind === 'checkbox') {
      body[f.key] = !!value;
    } else if (value !== '' && value !== null && value !== undefined) {
      body[f.key] = f.kind === 'number' ? Number(value) : value;
    }
  });
  if (!replace && type.key === 'database') body.db_kind = form.db_kind;
  return body;
};

// Campos obrigatórios que faltam (a mensagem exata vem do servidor; isto só evita o envio vazio).
export const missingFields = (type, form, { replace = false } = {}) =>
  visibleFields(type, form)
    .filter(f => {
      if (f.optional || f.kind === 'checkbox' || f.kind === 'select')
        return false;
      if (replace && (f.secret || f.key === 'name')) return false;
      if (
        type.key === 'database' &&
        f.key === 'database' &&
        form.db_kind === 'mongo'
      )
        return false;
      return (
        form[f.key] === '' || form[f.key] === null || form[f.key] === undefined
      );
    })
    .map(f => f.key);
