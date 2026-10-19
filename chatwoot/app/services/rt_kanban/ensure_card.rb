# Garante o cartão de uma conversa na etapa inicial, no fim da coluna. Idempotente.
class RtKanban::EnsureCard
  def self.call(conversation, source: 'system')
    board = RtKanban::EnsureBoard.call(conversation.account)
    existing = RtKanban::Card.find_by(conversation_id: conversation.id)
    return existing if existing

    RtKanban::Card.transaction do
      stage = RtKanban::Stage.lock.find(board.initial_stage.id)
      last = RtKanban::Card.where(stage_id: stage.id).maximum(:position) || 0
      card = RtKanban::Card.create!(account_id: conversation.account_id, board_id: board.id, stage_id: stage.id,
                                    conversation_id: conversation.id, position: last + RtKanban::Card::GAP)
      board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
      RtKanban::Event.create!(account_id: conversation.account_id, board_id: board.id, card_id_snapshot: card.id,
                              conversation_id_snapshot: conversation.id, to_stage_id_snapshot: stage.id, action: 'created',
                              source: source, to_position: card.position, to_lock_version: card.lock_version,
                              board_revision_after: board.revision, created_at: Time.current)
      card
    end
  rescue ActiveRecord::RecordNotUnique
    RtKanban::Card.find_by!(conversation_id: conversation.id)
  end
end
