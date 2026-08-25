# Produto-10 (25/08/2026): Facebook não oficial -- credencial é a sessão do
# navegador (cookies capturados via login guiado, oauth-browser), não uma
# API key. Mesmo padrão de Channel::Wapi/Channel::EvolutionApi, com
# `cookies` cifrado pelo Rails (ActiveRecord Encryption) em vez de token.
class Channel::FacebookUnofficial < ApplicationRecord
  include Channelable

  self.table_name = 'channel_facebook_unofficial'

  encrypts :cookies if Chatwoot.encryption_configured?

  before_validation :ensure_webhook_verify_token

  validates :cookies, presence: true

  def name
    'Facebook Unoficial'
  end

  def callback_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/facebook_unofficial/#{id}?verify_token=#{webhook_verify_token}"
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

  private

  def ensure_webhook_verify_token
    self.webhook_verify_token ||= SecureRandom.hex(16)
  end
end
