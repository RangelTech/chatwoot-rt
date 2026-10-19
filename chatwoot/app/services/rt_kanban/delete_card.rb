# Chamado dentro da transação de exclusão da Conversation: grava o evento e remove o cartão.
class RtKanban::DeleteCard
  def self.call(conversation)
    card = RtKanban::Card.find_by(conversation_id: conversation.id)
    return unless card

    board = card.board
    board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
    RtKanban::Event.create!(account_id: card.account_id, board_id: board.id, card_id_snapshot: card.id,
                            conversation_id_snapshot: conversation.id, from_stage_id_snapshot: card.stage_id,
                            action: 'deleted', source: 'system', board_revision_after: board.revision, created_at: Time.current)
    card.destroy!
  end
end
