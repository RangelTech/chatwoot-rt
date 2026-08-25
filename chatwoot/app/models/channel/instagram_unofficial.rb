# Produto-10 (25/08/2026): Instagram não oficial -- mesmo desenho de
# Channel::FacebookUnofficial (ver esse arquivo pro raciocínio completo).
class Channel::InstagramUnofficial < ApplicationRecord
  include Channelable

  self.table_name = 'channel_instagram_unofficial'

  encrypts :cookies if Chatwoot.encryption_configured?

  before_validation :ensure_webhook_verify_token

  validates :cookies, presence: true

  def name
    'Instagram Unoficial'
  end

  def callback_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/instagram_unofficial/#{id}?verify_token=#{webhook_verify_token}"
  end

  def cookies_jar
    JSON.parse(cookies)
  rescue JSON::ParserError, TypeError
    []
  end

  def cookies_jar=(lista)
    self.cookies = lista.to_json
  end

  def connected?
    connection_status['state'] == 'open'
  end

  def client
    SocialUnofficial::InstagramClient.new(cookies_jar: cookies_jar)
  end

  private

  def ensure_webhook_verify_token
    self.webhook_verify_token ||= SecureRandom.hex(16)
  end
end
