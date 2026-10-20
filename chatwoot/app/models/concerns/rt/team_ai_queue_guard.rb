# Fase F (F-1): nenhum caminho (UI, API, Super Admin, console) coloca membro humano numa fila "Gerenciada por IA",
# nem liga a atribuicao automatica nela, nem exclui fila com conversas abertas sem destino.
module Rt::TeamAiQueueGuard
  extend ActiveSupport::Concern

  prepended do
    attr_accessor :rt_move_open_conversations_to

    validate :rt_ai_queue_no_auto_assign
    before_destroy :rt_require_destination_for_open_conversations, prepend: true
  end

  def ai_queue?
    Rt::QueueBinding.ia.exists?(team_id: id)
  end

  def add_members(user_ids)
    if ai_queue? && user_ids.present?
      errors.add(:base, 'AI-managed queue cannot have human members')
      raise ActiveRecord::RecordInvalid, self
    end
    super
  end

  private

  def rt_ai_queue_no_auto_assign
    errors.add(:allow_auto_assign, 'must be disabled in an AI-managed queue') if persisted? && allow_auto_assign && ai_queue?
  end

  def rt_require_destination_for_open_conversations
    return unless Rt::QueueBinding.exists?(team_id: id)

    open_ids = conversations.where.not(status: :resolved).pluck(:id)
    return if open_ids.empty?

    if rt_move_open_conversations_to.present?
      target = account.teams.find(rt_move_open_conversations_to)
      conversations.where(id: open_ids).find_each { |c| c.update!(team: target) }
    else
      errors.add(:base, 'queue has open conversations: choose a destination')
      throw :abort
    end
  end
end
