class RtKanban::Board < ApplicationRecord
  self.table_name = 'rt_kanban_boards'

  DEFAULT_STAGES = [
    ['Novo', '#3b82f6', true], ['Em atendimento', '#f59e0b', false],
    ['Aguardando cliente', '#8b5cf6', false], ['Concluído', '#10b981', false]
  ].freeze

  belongs_to :account
  has_many :stages, -> { order(:position) }, class_name: 'RtKanban::Stage', dependent: :destroy
  has_many :cards, class_name: 'RtKanban::Card', dependent: :destroy

  validates :name, presence: true

  def initial_stage
    stages.find_by!(initial: true)
  end
end
