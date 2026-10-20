// Estado do painel "Pensando…" a partir dos eventos do stream (thinking, step, subagents).

// Um passo por linha: "start" abre; "done"/"error" fecha o mesmo rótulo; ordem preservada.
export const upsertStep = (steps, data) => {
  if (!data?.label) return steps;
  if (data.status === 'start')
    return [...steps, { label: data.label, status: 'start' }];
  const next = steps.map(s => ({ ...s }));
  for (let i = next.length - 1; i >= 0; i -= 1) {
    if (next[i].label === data.label && next[i].status === 'start') {
      next[i].status = data.status;
      return next;
    }
  }
  return [...next, { label: data.label, status: data.status }];
};

export const parseSubagents = data => ({
  active: Math.max(0, Number(data?.active) || 0),
  total: Math.max(0, Number(data?.total) || 0),
});

// O painel aparece enquanto a resposta ainda não começou ou enquanto algo segue em andamento.
export const isWorking = ({ sending, lastContent, steps, subagents }) => {
  if (!sending) return false;
  const busy =
    steps.some(s => s.status === 'start') || (subagents?.active || 0) > 0;
  return !lastContent || busy;
};
