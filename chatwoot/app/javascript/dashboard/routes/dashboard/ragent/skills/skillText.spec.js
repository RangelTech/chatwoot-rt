import {
  composeSkill,
  cronFromFrequency,
  describeCron,
  frequencyFromCron,
  parseSkill,
  slugify,
} from './skillText';

describe('skillText', () => {
  it('builds skill names with the personal prefix only when asked', () => {
    expect(slugify('Resumo de Reunião!')).toBe('resumo-de-reuniao');
    expect(slugify('Resumo de Reunião!', true)).toBe('u-resumo-de-reuniao');
    expect(slugify('   ', true)).toBe('');
  });

  it('composes and parses a skill without losing extra header fields', () => {
    const content = composeSkill({
      name: 'cobranca',
      description: 'Cobra: clientes em atraso',
      body: '# Passos\n\nLigue.',
      extra: ['license: interna'],
    });
    expect(content.startsWith('---\nname: cobranca\n')).toBe(true);
    const parsed = parseSkill(content);
    expect(parsed).toMatchObject({
      name: 'cobranca',
      description: 'Cobra: clientes em atraso',
      body: '# Passos\n\nLigue.\n',
      extra: ['license: interna'],
    });
    expect(parseSkill(composeSkill(parsed)).description).toBe(
      parsed.description
    );
  });

  it('treats text without a header as body only', () => {
    expect(parseSkill('so texto')).toMatchObject({
      name: '',
      body: 'so texto',
    });
  });

  it('round-trips frequencies and cron', () => {
    const cases = [
      [{ kind: 'daily', time: '08:30' }, '30 8 * * *'],
      [{ kind: 'weekly', time: '09:00', weekdays: [5, 1] }, '0 9 * * 1,5'],
      [{ kind: 'monthly', time: '07:15', day: 10 }, '15 7 10 * *'],
      [{ kind: 'hourly', minute: 20 }, '20 * * * *'],
    ];
    cases.forEach(([freq, cron]) => {
      expect(cronFromFrequency(freq)).toBe(cron);
      expect(frequencyFromCron(cron).kind).toBe(freq.kind);
    });
    expect(frequencyFromCron('*/5 * * * *')).toBeNull();
    expect(frequencyFromCron('0 9 1-5 * *')).toBeNull();
    expect(frequencyFromCron('lixo')).toBeNull();
  });

  it('describes known crons and falls back to the raw expression', () => {
    const t = (key, vars) => `${key}:${JSON.stringify(vars)}`;
    const days = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sab'];
    expect(describeCron('0 9 * * 1,3', t, days)).toContain('"days":"seg, qua"');
    expect(describeCron('*/5 * * * *', t, days)).toBe('*/5 * * * *');
  });
});
