import { describe, it, expect } from 'vitest';
import { isWorking, parseSubagents, upsertStep } from './progress';

describe('upsertStep', () => {
  it('abre o passo no start e fecha o mesmo rótulo no done', () => {
    let steps = upsertStep([], { label: 'Consultando dados', status: 'start' });
    steps = upsertStep(steps, { label: 'Lendo planilha', status: 'start' });
    steps = upsertStep(steps, { label: 'Consultando dados', status: 'done' });
    expect(steps).toEqual([
      { label: 'Consultando dados', status: 'done' },
      { label: 'Lendo planilha', status: 'start' },
    ]);
  });

  it('marca erro e não muta o array anterior', () => {
    const before = upsertStep([], { label: 'A', status: 'start' });
    const after = upsertStep(before, { label: 'A', status: 'error' });
    expect(before[0].status).toBe('start');
    expect(after[0].status).toBe('error');
  });

  it('o mesmo rótulo duas vezes fecha o mais recente em aberto', () => {
    let steps = upsertStep([], { label: 'A', status: 'start' });
    steps = upsertStep(steps, { label: 'A', status: 'done' });
    steps = upsertStep(steps, { label: 'A', status: 'start' });
    steps = upsertStep(steps, { label: 'A', status: 'done' });
    expect(steps.map(s => s.status)).toEqual(['done', 'done']);
  });

  it('done sem start vira linha; sem rótulo é ignorado', () => {
    expect(upsertStep([], { label: 'X', status: 'done' })).toEqual([
      { label: 'X', status: 'done' },
    ]);
    expect(upsertStep([], { status: 'start' })).toEqual([]);
  });
});

describe('parseSubagents', () => {
  it('lê active/total com segurança', () => {
    expect(parseSubagents({ active: 3, total: 3 })).toEqual({
      active: 3,
      total: 3,
    });
    expect(parseSubagents({ active: '2', total: 5 })).toEqual({
      active: 2,
      total: 5,
    });
    expect(parseSubagents({ active: -1, total: 'x' })).toEqual({
      active: 0,
      total: 0,
    });
    expect(parseSubagents(undefined)).toEqual({ active: 0, total: 0 });
  });
});

describe('isWorking', () => {
  const base = {
    sending: true,
    lastContent: '',
    steps: [],
    subagents: { active: 0 },
  };
  it('mostra enquanto não há resposta', () => {
    expect(isWorking(base)).toBe(true);
  });
  it('some quando a resposta já corre e nada está pendente', () => {
    expect(
      isWorking({
        ...base,
        lastContent: 'oi',
        steps: [{ label: 'A', status: 'done' }],
      })
    ).toBe(false);
  });
  it('continua enquanto há passo aberto ou subagente ativo', () => {
    expect(
      isWorking({
        ...base,
        lastContent: 'oi',
        steps: [{ label: 'A', status: 'start' }],
      })
    ).toBe(true);
    expect(
      isWorking({ ...base, lastContent: 'oi', subagents: { active: 2 } })
    ).toBe(true);
  });
  it('nunca mostra fora de um envio', () => {
    expect(isWorking({ ...base, sending: false })).toBe(false);
  });
});
