import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { DRAG_OPTIONS } from './dragOptions';
import KanbanColumn from './KanbanColumn.vue';

describe('DRAG_OPTIONS', () => {
  it('usa arraste por ponteiro (forceFallback) para funcionar em toque e por CDP', () => {
    expect(DRAG_OPTIONS.forceFallback).toBe(true);
    expect(DRAG_OPTIONS.group).toBe('rt-kanban');
    expect(DRAG_OPTIONS.fallbackTolerance).toBeGreaterThan(0);
  });

  it('não deixa controles do cartão iniciarem arraste e preserva o clique', () => {
    expect(DRAG_OPTIONS.filter).toContain('button');
    expect(DRAG_OPTIONS.preventOnFilter).toBe(false);
  });
});

describe('KanbanColumn', () => {
  it('liga as opções de arraste no Draggable', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'pt_BR',
      messages: { pt_BR: {} },
      missingWarn: false,
    });
    const wrapper = mount(KanbanColumn, {
      props: {
        stage: { id: 1, name: 'Novo', count_visible: 1 },
        items: [{ id: 7, title: 'x' }],
        canEdit: false,
      },
      global: { plugins: [i18n], stubs: { KanbanCard: true, Button: true } },
    });
    const drag = wrapper.findComponent(Draggable);
    expect(drag.exists()).toBe(true);
    // vuedraggable repassa as opções ao SortableJS como atributos.
    expect(drag.vm.$attrs.forceFallback).toBe(true);
    expect(drag.vm.$attrs.group).toBe('rt-kanban');
  });
});
