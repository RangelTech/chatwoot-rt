import { readFileSync } from 'fs';
import { resolve } from 'path';
import { routes } from '../ragent.routes';

// Regressao 23/10/2026: um item do menu apontava para uma rota inexistente e o Vue Router
// derrubava o grupo IA e o Kanban inteiros. Todo nome de rota do menu lateral precisa existir.
const sidebar = readFileSync(
  resolve(__dirname, '../../../../components-next/sidebar/Sidebar.vue'),
  'utf8'
);
const kanban = readFileSync(
  resolve(__dirname, '../../kanban/kanban.routes.js'),
  'utf8'
);

describe('menu lateral: rotas do LUAR existem', () => {
  const names = [
    ...new Set(
      [...sidebar.matchAll(/accountScopedRoute\(\s*'((?:ragent|rt)_[a-z_]+)'/g)].map(
        m => m[1]
      )
    ),
  ];

  it('encontra os itens do menu IA e Kanban', () => {
    expect(names).toEqual(
      expect.arrayContaining(['ragent_chat', 'ragent_routines', 'rt_kanban'])
    );
  });

  it.each(names)('rota %s esta registrada', name => {
    const known = routes.some(r => r.name === name) || kanban.includes(`'${name}'`);
    expect(known).toBe(true);
  });
});
