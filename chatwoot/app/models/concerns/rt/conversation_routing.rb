# Fase F: registra cada troca de fila e cada devolucao (responsavel solto numa fila de IA). So em caixas fora do legado.
module Rt::ConversationRouting
  extend ActiveSupport::Concern

  prepended do
    after_commit :rt_record_routing_change, on: :update
  end

  private

  def rt_record_routing_change
    return if Rt::InboxEntryQueue.mode_for(inbox_id) == 'legado'

    if saved_change_to_team_id?
      from, to = saved_change_to_team_id
      Rt::RoutingEvent.record!(conversation: self, from_team_id: from, to_team_id: to, actor_kind: Current.user ? 'human' : 'system',
                               actor_id: Current.user&.id, reason: from.nil? && Current.user.nil? ? 'fila_de_entrada' : 'troca_de_fila')
    elsif saved_change_to_assignee_id? && assignee_id.nil? && team_id && Rt::QueueBinding.ia.exists?(team_id: team_id)
      Rt::RoutingEvent.record!(conversation: self, from_team_id: team_id, to_team_id: team_id, actor_kind: Current.user ? 'human' : 'system',
                               actor_id: Current.user&.id, reason: 'devolucao_a_ia')
    end
  end
end
