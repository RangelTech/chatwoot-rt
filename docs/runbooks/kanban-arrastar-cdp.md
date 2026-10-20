# Kanban: testar o arraste por CDP

O quadro usa vuedraggable (SortableJS) com `forceFallback` (ver `kanban/dragOptions.js`). Em vez do
drag-and-drop nativo do HTML5, o Sortable acompanha o ponteiro por eventos de mouse/toque, então o
arraste funciona no celular e pode ser exercitado por CDP sem `Input.setInterceptDrags`.

## Por que o teste anterior falhou
O CDP não inicia o arraste nativo (nenhum `dragIntercepted`) e eventos `dragstart` sintéticos não
passam pelo caminho que o Sortable usa. Com `forceFallback` o Sortable escuta `mousedown`, `mousemove`
e `mouseup`, e eventos reais de mouse do CDP bastam.

## Passo a passo (mouse real)
1. Abra `/app/accounts/<id>/kanban` e meça o centro do cartão de origem e o da coluna de destino
   (`getBoundingClientRect`, ajustando pela escala da página se houver).
2. `Input.dispatchMouseEvent` na ordem, com pausas de 30 a 50 ms entre eles:
   - `mousePressed` (button `left`, buttons `1`, clickCount `1`) no centro do cartão;
   - 5 a 10 `mouseMoved` (buttons `1`) em passos regulares até o destino. O primeiro movimento
     precisa passar de 4 px (tolerância) para virar arraste; os intermediários deixam o Sortable
     calcular a posição;
   - `mouseReleased` (button `left`) sobre a coluna de destino.
3. Confira: o cartão aparece na coluna de destino, o contador da coluna mudou e, após recarregar,
   o cartão continua lá (o movimento persiste no servidor).

Em toque: `Input.dispatchTouchEvent` (`touchStart`, vários `touchMove`, `touchEnd`) com 150 ms de
espera entre `touchStart` e o primeiro `touchMove`, que é o atraso de pressionar para arrastar.

## Cuidados
- Botões, links e campos do cartão não iniciam arraste (`filter`), por isso o menu "Mover para"
  continua funcionando por clique.
- Sem passos intermediários o Sortable não detecta o alvo: não vá direto do `mousePressed` ao
  `mouseReleased`.
- Teste de unidade: `kanban/dragOptions.spec.js` garante que a coluna usa `forceFallback`.
