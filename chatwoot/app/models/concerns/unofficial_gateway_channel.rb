# Fase CH: miolo comum dos canais não oficiais conectados pelo gateway de canais
# (usuário/senha ou QR). Sem cookie e sem polling: a entrada é por webhook assinado
# e a saída por chamada ao gateway. O segredo do webhook é cifrado quando as chaves
# do ActiveRecord Encryption estão configuradas.
module UnofficialGatewayChannel
  extend ActiveSupport::Concern

  STATES = %w[pending_auth awaiting_2fa awaiting_challenge connected degraded reauth_required disconnected revoked].freeze
  CHANNEL_TYPES = {
    'instagram_unofficial' => 'Channel::InstagramUnofficial',
    'messenger_unofficial' => 'Channel::MessengerUnofficial',
    'whatsapp_unofficial' => 'Channel::WhatsappUnofficial',
    'tiktok_unofficial' => 'Channel::TiktokUnofficial'
  }.freeze
  PROVIDERS = {
    'instagram' => 'Channel::InstagramUnofficial',
    'messenger' => 'Channel::MessengerUnofficial',
    'whatsapp' => 'Channel::WhatsappUnofficial',
    'tiktok' => 'Channel::TiktokUnofficial'
  }.freeze

  included do
    include Channelable

    encrypts :webhook_secret if Chatwoot.encryption_configured?

    validates :state, inclusion: { in: STATES }, allow_nil: true
    validates :connection_id, uniqueness: true, allow_nil: true
  end

  def self.channel_class_for_type(channel_type)
    CHANNEL_TYPES[channel_type.to_s]&.constantize
  end

  def self.channel_class_for_provider(provider)
    PROVIDERS[provider.to_s]&.constantize
  end

  def channel_type_slug
    self.class.name.demodulize.underscore
  end

  def provider
    channel_type_slug.delete_suffix('_unofficial')
  end

  def connected?
    state == 'connected'
  end

  # Canal legado, criado com cookie: precisa reconectar pelo assistente.
  def reauth_required?
    state == 'reauth_required'
  end

  def callback_url
    base = ENV.fetch('CHANNELS_WEBHOOK_BASE_URL', ENV.fetch('FRONTEND_URL', ''))
    "#{base}/webhooks/channels/#{channel_type_slug}/#{id}"
  end

  def generate_webhook_secret!
    self.webhook_secret = SecureRandom.hex(32)
  end

  def apply_connection_state!(new_state, error_code: nil, at: Time.current)
    return unless STATES.include?(new_state)

    update!(state: new_state, last_error_code: error_code, last_activity_at: at)
  end
end
