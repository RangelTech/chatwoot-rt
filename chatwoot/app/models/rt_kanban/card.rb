class RtKanban::Card < ApplicationRecord
  self.table_name = 'rt_kanban_cards'

  GAP = 1024

  belongs_to :account
  belongs_to :board, class_name: 'RtKanban::Board'
  belongs_to :stage, class_name: 'RtKanban::Stage'
  belongs_to :conversation

  validate :same_account

  private

  def same_account
    return if [board&.account_id, stage&.board&.account_id, conversation&.account_id].all?(account_id)

    errors.add(:base, 'board, stage and conversation must belong to the same account')
  end
end
