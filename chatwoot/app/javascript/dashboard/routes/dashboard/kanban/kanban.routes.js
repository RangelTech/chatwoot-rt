import { frontendURL } from '../../../helper/URLHelper';
import KanbanBoard from './KanbanBoard.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    name: 'rt_kanban',
    meta: { permissions: ['administrator', 'agent'] },
    component: KanbanBoard,
  },
];
