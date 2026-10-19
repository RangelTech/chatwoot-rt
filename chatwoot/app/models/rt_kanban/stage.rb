class RtKanban::Stage < ApplicationRecord
  self.table_name = 'rt_kanban_stages'

  belongs_to :board, class_name: 'RtKanban::Board'
  has_many :cards, class_name: 'RtKanban::Card', dependent: :restrict_with_error

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }
  validates :position, numericality: { only_integer: true }
end
