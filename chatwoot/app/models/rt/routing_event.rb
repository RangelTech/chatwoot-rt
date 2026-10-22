# Fase F: registro (append-only) de cada transferencia entre filas.
class Rt::RoutingEvent < ApplicationRecord
  self.table_name = 'rt_routing_events'

  ACTORS = %w[system human ia].freeze
  validates :actor_kind, inclusion: { in: ACTORS }
  validates :account_id, :conversation_id, presence: true

  before_update { throw :abort }
  before_destroy { throw :abort }

  def self.record!(conversation:, from_team_id:, to_team_id:, actor_kind:, actor_id: nil, reason: nil, run_id: nil)
    create!(account_id: conversation.account_id, conversation_id: conversation.id, from_team_id: from_team_id,
            to_team_id: to_team_id, actor_kind: actor_kind, actor_id: actor_id, reason: reason, run_id: run_id)
  end
end
