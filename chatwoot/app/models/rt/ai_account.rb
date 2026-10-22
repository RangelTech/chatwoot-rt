# == Schema Information
#
# Table name: rt_ai_accounts
#
#  id               :bigint           not null, primary key
#  ai_state         :string           default("pending"), not null
#  flags            :jsonb            not null
#  last_error       :text
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  engine_tenant_id :uuid
#
class Rt::AiAccount < ApplicationRecord
  self.table_name = 'rt_ai_accounts'

  STATES = %w[pending active failed suspended].freeze
  # Flags por Account (spec 10 §0.6): o Chatwoot decide, o motor só obedece.
  DEFAULT_FLAGS = {
    'ai_enabled' => false, 'chat_enabled' => false, 'chat_landing_enabled' => false, 'harness_enabled' => false,
    'graph_enabled' => false, 'environment_enabled' => false, 'kanban_enabled' => false,
    'outbound_enabled' => false
  }.freeze

  belongs_to :account

  validates :ai_state, inclusion: { in: STATES }

  def effective_flags
    DEFAULT_FLAGS.merge(flags)
  end
end
