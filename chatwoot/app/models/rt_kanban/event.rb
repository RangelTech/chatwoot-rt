# Auditoria append-only: sem FK para entidades que podem ser excluídas.
class RtKanban::Event < ApplicationRecord
  self.table_name = 'rt_kanban_events'

  ACTIONS = %w[created moved deleted stage_changed].freeze

  validates :action, inclusion: { in: ACTIONS }

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy { raise ActiveRecord::ReadOnlyRecord }
end
