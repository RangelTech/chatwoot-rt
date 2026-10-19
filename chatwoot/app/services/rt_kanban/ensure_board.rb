# Um quadro por Account, com as etapas iniciais. Idempotente.
class RtKanban::EnsureBoard
  def self.call(account)
    RtKanban::Board.transaction do
      board = RtKanban::Board.find_or_create_by!(account_id: account.id)
      if board.stages.none?
        RtKanban::Board::DEFAULT_STAGES.each_with_index do |(name, color, initial), index|
          board.stages.create!(name: name, color: color, initial: initial, position: (index + 1) * RtKanban::Card::GAP)
        end
      end
      board
    end
  end
end
