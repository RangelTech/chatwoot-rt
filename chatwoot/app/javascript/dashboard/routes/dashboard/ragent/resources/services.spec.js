import {
  actionsFor,
  formatUptime,
  normalizeServices,
  originKey,
  portText,
  stateClass,
} from './services';

describe('services helpers', () => {
  it('formats uptime in pt-BR units', () => {
    expect(formatUptime(5)).toBe('5 s');
    expect(formatUptime(125)).toBe('2 min');
    expect(formatUptime(3600)).toBe('1 h');
    expect(formatUptime(3900)).toBe('1 h 5 min');
    expect(formatUptime(90000)).toBe('1 d 1 h');
    expect(formatUptime(null)).toBe('—');
    expect(formatUptime(-1)).toBe('—');
  });

  it('normalizes malformed payloads to an empty list', () => {
    const empty = normalizeServices(undefined);
    expect(empty.servicos).toEqual([]);
    expect(empty.soltos).toEqual([]);
    expect(normalizeServices({ servicos: 'x', soltos: null }).servicos).toEqual([]);
    expect(normalizeServices({ servicos: [{}, { nome: 'web' }] }).servicos).toHaveLength(1);
    expect(normalizeServices({ ambiente: 'parado' }).ambiente).toBe('parado');
  });

  it('offers only the actions that make sense for the state', () => {
    expect(actionsFor('rodando')).toEqual(['restart', 'stop']);
    expect(actionsFor('parado')).toEqual(['start']);
    expect(actionsFor('reiniciando')).toEqual(['stop']);
  });

  it('has safe fallbacks for ports, state color and origin', () => {
    expect(portText([])).toBe('—');
    expect(portText([8000, 9000])).toBe('8000, 9000');
    expect(stateClass('desconhecido')).toContain('n-slate');
    expect(originKey({ criado_pelo_agente: true })).toBe('AGENT');
    expect(originKey({})).toBe('SUPERVISED');
  });
});
