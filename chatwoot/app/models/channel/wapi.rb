# == Schema Information
#
# Table name: channel_wapi
#
#  id                          :bigint           not null, primary key
#  connection_status           :jsonb            not null
#  connection_status_checked_at :datetime
#  project_id                  :string           not null
#  token                       :string           not null
#  webhook_verify_token        :string           not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :integer          not null
#
# Indexes
#
#  index_channel_wapi_on_project_id  (project_id) UNIQUE
#  index_channel_wapi_on_account_id  (account_id)
#

# Channel::Wapi is a non-official WhatsApp provider (WAPI) integration.
# Unlike Channel::Whatsapp (built around Meta's Cloud API / 360dialog), this is a
# thin, generic HTTP channel: the tenant supplies a project id + token, we expose a
# webhook callback URL for WAPI to push messages to, and we can actively probe
# WAPI's own status/ping endpoint to report connection health.
#
# See personal-skills/mega-spec-agent-llm/produto-06-chatwoot-fork-whatsapp-extends-ai-assist.md
# section 3a.
class Channel::Wapi < ApplicationRecord
  include Channelable

  self.table_name = 'channel_wapi'
  EDITABLE_ATTRS = [:project_id, :token].freeze

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  if Chatwoot.encryption_configured?
    encrypts :token
  end

  before_validation :ensure_webhook_verify_token

  validates :project_id, presence: true, uniqueness: true
  validates :token, presence: true

  def name
    'WAPI'
  end

  # Public callback URL shown in the UI for the tenant to paste into the WAPI panel.
  def callback_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/wapi/#{project_id}"
  end

  # Calls WAPI's status/ping endpoint and persists the result so the health
  # indicator (green/red) can be read cheaply from the DB without hitting the
  # external API on every page load.
  def test_connection!
    result = Wapi::ConnectionTestService.new(channel: self).perform
    update!(connection_status: result, connection_status_checked_at: Time.current)
    result
  end

  def connected?
    connection_status['status'] == 'connected'
  end

  private

  def ensure_webhook_verify_token
    self.webhook_verify_token ||= SecureRandom.hex(16)
  end
end
