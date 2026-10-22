// Serviços em execução do ambiente (AMB-3): normalização do que o motor devolve e rótulos em pt-BR.
export const REFRESH_MS = 15000;

export const formatUptime = seconds => {
  const total = Number(seconds);
  if (seconds === null || seconds === undefined || Number.isNaN(total) || total < 0) {
    return '—';
  }
  if (total < 60) return `${Math.floor(total)} s`;
  if (total < 3600) return `${Math.floor(total / 60)} min`;
  if (total < 86400) {
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    return m ? `${h} h ${m} min` : `${h} h`;
  }
  const d = Math.floor(total / 86400);
  const h = Math.floor((total % 86400) / 3600);
  return h ? `${d} d ${h} h` : `${d} d`;
};

const list = value => (Array.isArray(value) ? value : []);

// Resposta ausente ou malformada nunca derruba a tela: vira "sem serviços".
export const normalizeServices = data => {
  const body = data && typeof data === 'object' ? data : {};
  return {
    ambiente: typeof body.ambiente === 'string' ? body.ambiente : 'ativo',
    servicos: list(body.servicos).filter(s => s && s.nome),
    soltos: list(body.soltos),
    conteineres: list(body.conteineres),
    docker: !!body.docker,
  };
};

export const STATE_CLASS = {
  rodando: 'bg-n-teal-3 text-n-teal-11',
  reiniciando: 'bg-n-amber-3 text-n-amber-11',
  parado: 'bg-n-alpha-2 text-n-slate-11',
};

export const stateClass = estado =>
  STATE_CLASS[estado] || 'bg-n-alpha-2 text-n-slate-11';

// Ações oferecidas conforme o estado atual: parar só quando está de pé, iniciar só quando parado.
export const actionsFor = estado => {
  if (estado === 'rodando') return ['restart', 'stop'];
  if (estado === 'reiniciando') return ['stop'];
  return ['start'];
};

export const portText = ports => {
  const list_ = list(ports);
  return list_.length ? list_.join(', ') : '—';
};

export const originKey = service =>
  service.criado_pelo_agente ? 'AGENT' : 'SUPERVISED';
