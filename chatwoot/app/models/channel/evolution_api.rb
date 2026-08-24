class Channel::EvolutionApi < ApplicationRecord
  include Channelable

  self.table_name = 'channel_evolution_api'
  EDITABLE_ATTRS = [:instance_name, :api_url, :api_key].freeze

  encrypts :api_key if Chatwoot.encryption_configured?

  before_validation :ensure_webhook_verify_token
  before_destroy :deprovision_on_bridge!

  validates :instance_name, :api_url, :api_key, presence: true
  validates :instance_name, uniqueness: true
  validates :api_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  def name
    'Evolution API'
  end

  def callback_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/evolution/#{instance_name}?verify_token=#{webhook_verify_token}"
  end

  def connect!
    result = Evolution::Client.new(channel: self).connect
    update!(
      qr_code: result[:qr_code],
      connection_status: result[:connection_status],
      connection_status_checked_at: Time.current
    )
    result
  end

  def reconnect!
    result = Evolution::Client.new(channel: self).reconnect
    update!(
      qr_code: result[:qr_code],
      connection_status: result[:connection_status],
      connection_status_checked_at: Time.current
    )
    result
  end

  def connected?
    connection_status['state'] == 'open'
  end

  private

  def ensure_webhook_verify_token
    self.webhook_verify_token ||= SecureRandom.hex(16)
  end

  # Achado real 24/08/2026: sem isso, apagar a inbox nunca desligava a
  # instância real na VPS -- reconectar reaproveitava a mesma sessão
  # WhatsApp já logada, pulando o QR (ver produto-09 seção 5/deprovision).
  def deprovision_on_bridge!
    Evolution::DeprovisioningService.new(channel: self).call
  rescue Evolution::DeprovisioningService::DeprovisioningError => e
    errors.add(:base, e.message)
    throw :abort
  end
end
