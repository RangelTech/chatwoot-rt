// Texto de skill (SKILL.md) e frequência de rotina: conversões puras, sem rede nem Vue.

export const PERSONAL_PREFIX = 'u-';

export const slugify = (value, personal = false) => {
  const slug = String(value || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 58);
  if (!slug) return '';
  return personal ? `${PERSONAL_PREFIX}${slug}` : slug;
};

const unquote = raw => {
  const value = String(raw || '').trim();
  if (value.startsWith('"')) {
    try {
      return JSON.parse(value);
    } catch (error) {
      return value.slice(1, -1);
    }
  }
  if (value.startsWith("'") && value.endsWith("'")) {
    return value.slice(1, -1).replace(/''/g, "'");
  }
  return value;
};

// { name, description, body, extra } a partir do SKILL.md; `extra` guarda os demais campos do
// cabeçalho para a edição não apagar nada que a pessoa não vê.
export const parseSkill = content => {
  const raw = String(content || '');
  const text = raw.charCodeAt(0) === 0xfeff ? raw.slice(1) : raw;
  const lines = text.split('\n');
  const empty = { name: '', description: '', body: text, extra: [] };
  if (lines[0]?.trim() !== '---') return empty;
  const end = lines.findIndex((line, i) => i > 0 && line.trim() === '---');
  if (end < 0) return empty;
  const out = { name: '', description: '', extra: [] };
  lines.slice(1, end).forEach(line => {
    const m = line.match(/^(name|description):\s*(.*)$/);
    if (m) out[m[1]] = unquote(m[2]);
    else out.extra.push(line);
  });
  out.body = lines
    .slice(end + 1)
    .join('\n')
    .replace(/^\n+/, '');
  return out;
};

export const composeSkill = ({ name, description, body, extra = [] }) => {
  const head = [
    `name: ${name}`,
    `description: ${JSON.stringify(String(description || '').trim())}`,
    ...extra,
  ];
  return `---\n${head.join('\n')}\n---\n${String(body || '').trim()}\n`;
};

// ---- Frequência amigável <-> cron

export const DEFAULT_FREQUENCY = {
  kind: 'daily',
  time: '08:00',
  minute: 0,
  weekdays: [1, 2, 3, 4, 5],
  day: 1,
};

const pad = n => String(n).padStart(2, '0');

export const cronFromFrequency = f => {
  const [hour, minute] = String(f.time || '08:00')
    .split(':')
    .map(Number);
  if (f.kind === 'hourly') return `${Number(f.minute) || 0} * * * *`;
  if (f.kind === 'daily') return `${minute} ${hour} * * *`;
  if (f.kind === 'weekly') {
    const days = [...new Set(f.weekdays)].sort((a, b) => a - b);
    return `${minute} ${hour} * * ${days.join(',')}`;
  }
  if (f.kind === 'monthly') return `${minute} ${hour} ${f.day} * *`;
  return '';
};

// Tenta reconhecer um cron simples; devolve null quando só dá para editar como "avançado".
export const frequencyFromCron = cron => {
  const parts = String(cron || '')
    .trim()
    .split(/\s+/);
  if (parts.length !== 5) return null;
  const [m, h, dom, mon, dow] = parts;
  const num = /^\d+$/;
  if (mon !== '*' || !num.test(m)) return null;
  if (h === '*' && dom === '*' && dow === '*') {
    return { ...DEFAULT_FREQUENCY, kind: 'hourly', minute: Number(m) };
  }
  if (!num.test(h)) return null;
  const time = `${pad(h)}:${pad(m)}`;
  if (dom === '*' && dow === '*')
    return { ...DEFAULT_FREQUENCY, kind: 'daily', time };
  if (dom === '*' && /^\d(,\d)*$/.test(dow)) {
    return {
      ...DEFAULT_FREQUENCY,
      kind: 'weekly',
      time,
      weekdays: dow.split(',').map(Number),
    };
  }
  if (num.test(dom) && dow === '*') {
    return { ...DEFAULT_FREQUENCY, kind: 'monthly', time, day: Number(dom) };
  }
  return null;
};

// Texto curto da frequência. `t` é o tradutor; `dayNames` os 7 nomes (domingo primeiro).
export const describeCron = (cron, t, dayNames) => {
  const f = frequencyFromCron(cron);
  if (!f) return cron;
  if (f.kind === 'hourly')
    return t('RAGENT.ROUTINE.DESC_HOURLY', { minute: pad(f.minute) });
  if (f.kind === 'daily')
    return t('RAGENT.ROUTINE.DESC_DAILY', { time: f.time });
  if (f.kind === 'weekly') {
    const days = f.weekdays.map(d => dayNames[d]).join(', ');
    return t('RAGENT.ROUTINE.DESC_WEEKLY', { days, time: f.time });
  }
  return t('RAGENT.ROUTINE.DESC_MONTHLY', { day: f.day, time: f.time });
};

export const TIMEZONES = [
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Belem',
  'America/Fortaleza',
  'America/Cuiaba',
  'America/Rio_Branco',
  'America/Noronha',
  'Europe/Lisbon',
  'UTC',
];
