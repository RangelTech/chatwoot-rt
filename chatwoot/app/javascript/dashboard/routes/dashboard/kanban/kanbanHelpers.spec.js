import { describe, it, expect } from 'vitest';
import {
  beforeCardIdAfterDrop,
  moveErrorKey,
  stageAnchor,
} from './kanbanHelpers';

describe('beforeCardIdAfterDrop', () => {
  const items = [{ id: 1 }, { id: 2 }, { id: 3 }];
  it('usa o vizinho seguinte como âncora', () => {
    expect(beforeCardIdAfterDrop(items, 0)).toBe(2);
    expect(beforeCardIdAfterDrop(items, 1)).toBe(3);
  });
  it('sem vizinho seguinte vai para o fim da coluna', () => {
    expect(beforeCardIdAfterDrop(items, 2)).toBeNull();
    expect(beforeCardIdAfterDrop([], 0)).toBeNull();
  });
});

describe('stageAnchor', () => {
  const stages = [{ id: 10 }, { id: 20 }, { id: 30 }, { id: 40 }];
  it('esquerda: antes da etapa anterior', () => {
    expect(stageAnchor(stages, 30, -1)).toBe(20);
    expect(stageAnchor(stages, 20, -1)).toBe(10);
  });
  it('direita: antes da etapa depois da seguinte; ao fim quando é a penúltima', () => {
    expect(stageAnchor(stages, 10, 1)).toBe(30);
    expect(stageAnchor(stages, 30, 1)).toBe('');
  });
  it('nas pontas ou id desconhecido não há movimento', () => {
    expect(stageAnchor(stages, 10, -1)).toBeNull();
    expect(stageAnchor(stages, 40, 1)).toBeNull();
    expect(stageAnchor(stages, 99, 1)).toBeNull();
  });
});

describe('moveErrorKey', () => {
  it('mapeia 409/422/403/404 e cai no genérico', () => {
    expect(moveErrorKey(409)).toBe('ERROR_CONFLICT');
    expect(moveErrorKey(422)).toBe('ERROR_INVALID');
    expect(moveErrorKey(403)).toBe('ERROR_FORBIDDEN');
    expect(moveErrorKey(404)).toBe('ERROR_NOT_FOUND');
    expect(moveErrorKey(500)).toBe('ERROR_GENERIC');
    expect(moveErrorKey(undefined)).toBe('ERROR_GENERIC');
  });
});
