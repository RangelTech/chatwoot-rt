# == Schema Information
#
# Table name: rt_outbox_events
#
#  id         :bigint           not null, primary key
#  attempts   :integer          default(0), not null
#  kind       :string           not null
#  last_error :text
#  run_at     :datetime         not null
#  state      :string           default("pending"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  occurred_at :datetime
#  user_id    :bigint
#
class Rt::OutboxEvent < ApplicationRecord
  self.table_name = 'rt_outbox_events'

  KINDS = %w[provision suspend resume deprovision member_revoked].freeze
  MAX_ATTEMPTS = 12

  validates :kind, inclusion: { in: KINDS }

  scope :due, -> { where(state: 'pending').where('run_at <= ?', Time.current).order(:id) }

  def backoff_seconds
    [30 * (2**attempts), 3600].min
  end
end
