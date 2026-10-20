import {
  formatBRL,
  formatBytes,
  formatDate,
  formatDuration,
  formatNumber,
  isDateKey,
  percent,
} from './format';

describe('format (telas de cadastros)', () => {
  it('formata data sem recuar o dia pelo fuso', () => {
    expect(formatDate('2026-10-19')).toBe('19/10/2026');
    expect(formatDate(null)).toBe('—');
    expect(formatDate('lixo')).toBe('lixo');
  });

  it('formata data e hora em pt-BR', () => {
    expect(formatDate('2026-10-19T14:05:00')).toMatch(/19\/10\/2026.*14:05/);
  });

  it('formata números com separador brasileiro', () => {
    expect(formatNumber(1234567)).toBe('1.234.567');
    expect(formatNumber(1234.5, 2)).toBe('1.234,50');
    expect(formatNumber(undefined)).toBe('—');
  });

  it('formata custo em R$ estimado', () => {
    expect(formatBRL(1)).toMatch(/R\$\s?5,50/);
    expect(formatBRL(null)).toBe('—');
  });

  it('formata tamanhos e durações', () => {
    expect(formatBytes(512)).toBe('512 B');
    expect(formatBytes(2048)).toBe('2,0 KB');
    expect(formatDuration(850)).toBe('850 ms');
    expect(formatDuration(2500)).toBe('2,5 s');
    expect(formatDuration(null)).toBe('—');
  });

  it('calcula porcentagem de uso e reconhece chaves de data', () => {
    expect(percent(512, 2048)).toBe(25);
    expect(percent(1, 0)).toBeNull();
    expect(isDateKey('last_activity_at')).toBe(true);
    expect(isDateKey('day')).toBe(true);
    expect(isDateKey('name')).toBe(false);
  });
});
