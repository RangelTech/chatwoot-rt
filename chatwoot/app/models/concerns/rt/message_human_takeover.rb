# Fase F (F-3): quando um humano escreve (mensagem publica) numa fila de IA que ainda nao tem responsavel, o Luar o
# marca como responsavel: o Chatwoot nao faz isso sozinho (F-0 b). So age em caixas com routing_mode = filas.
# Mensagens da propria IA chegam como usuario do Chatwoot (token da conta) e por isso carregam
# content_attributes.rt_origin = 'ia'; elas nunca contam como assuncao.
module Rt::MessageHumanTakeover
  extend ActiveSupport::Concern

  prepended do
    after_create_commit :rt_register_human_takeover
  end

  private

  def rt_register_human_takeover
    return unless rt_human_public_reply?

    conversation = self.conversation
    return if conversation.assignee_id.present? || conversation.resolved?
    return unless Rt::InboxEntryQueue.mode_for(conversation.inbox_id) == 'filas'
    return unless conversation.team_id && Rt::QueueBinding.ia.exists?(team_id: conversation.team_id)

    conversation.update!(assignee_id: sender_id)
    Rt::RoutingEvent.record!(conversation: conversation, from_team_id: conversation.team_id, to_team_id: conversation.team_id,
                             actor_kind: 'human', actor_id: sender_id, reason: 'assuncao_humana')
  end

  def rt_human_public_reply?
    outgoing? && !private? && sender_type == 'User' && sender_id.present? &&
      content_attributes.to_h['rt_origin'] != 'ia'
  end
end
