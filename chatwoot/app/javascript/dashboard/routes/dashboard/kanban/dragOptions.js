// Opções do arraste do quadro. `forceFallback` troca o drag-and-drop nativo do HTML5 (que não responde a
// eventos de mouse sintéticos nem ao CDP) pelo arraste por eventos de ponteiro do SortableJS: o mesmo
// caminho serve ao toque no celular e à automação (Input.dispatchMouseEvent).
export const DRAG_OPTIONS = Object.freeze({
  group: 'rt-kanban',
  animation: 150,
  forceFallback: true,
  // Pixels de tolerância antes de virar arraste: um clique simples (abrir cartão, menu) não arrasta.
  fallbackTolerance: 4,
  // No toque, segurar 150 ms antes de arrastar evita brigar com a rolagem da coluna.
  delay: 150,
  delayOnTouchOnly: true,
  touchStartThreshold: 4,
  // Controles do cartão nunca iniciam arraste.
  filter: 'button, a, select, input, textarea, [role="menu"]',
  preventOnFilter: false,
});
