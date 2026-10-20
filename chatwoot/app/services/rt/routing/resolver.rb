# Fase F (F-2): quem responde a esta conversa? Funcao pura sobre um retrato do estado (sem banco, sem rede).
#
#   Rt::Routing::Resolver.call(status:, team_id:, assignee_id:, entry_team_id:, binding:, agent_published:)
#   => { respondent: 'ia'|'humano'|'ninguem', agent: template_id|nil, queue_id:, reason:, apply_entry_queue: bool }
#
# Regras (spec 10, Fase F):
#   1. resolvida => ninguem
#   2. sem fila => aplica a fila de entrada da caixa e reavalia
#   3. responsavel humano => humano (a IA se cala)
#   4. fila de IA com modo piloto e agente publicado => ia
#   5. qualquer outro caso => humano
module Rt::Routing::Resolver
  QueueInfo = Struct.new(:respondent_kind, :mode, :template_id, keyword_init: true)

  module_function

  def call(status:, team_id: nil, assignee_id: nil, entry_team_id: nil, binding: nil, agent_published: false)
    return decision('ninguem', nil, team_id, 'resolvida') if status.to_s == 'resolved'

    apply_entry = false
    if team_id.nil?
      return decision('humano', nil, nil, assignee_id ? 'responsavel_humano' : 'sem_fila') if entry_team_id.nil? && assignee_id
      return decision('humano', nil, nil, 'sem_fila') if entry_team_id.nil?

      team_id = entry_team_id
      apply_entry = true
    end
    return decision('humano', nil, team_id, 'responsavel_humano', apply_entry) if assignee_id

    unless binding
      return decision('humano', nil, team_id, 'fila_sem_vinculo', apply_entry)
    end
    return decision('humano', nil, team_id, 'fila_humana', apply_entry) unless binding.respondent_kind == 'ia'
    return decision('humano', binding.template_id, team_id, 'modo_desligado', apply_entry) unless binding.mode == 'piloto'
    return decision('humano', binding.template_id, team_id, 'agente_nao_publicado', apply_entry) unless agent_published

    decision('ia', binding.template_id, team_id, 'fila_ia', apply_entry)
  end

  def decision(respondent, agent, queue_id, reason, apply_entry = false)
    { respondent: respondent, agent: agent, queue_id: queue_id, reason: reason, apply_entry_queue: apply_entry }
  end
end
