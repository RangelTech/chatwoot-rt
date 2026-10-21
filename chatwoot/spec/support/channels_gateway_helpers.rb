# frozen_string_literal: true

require 'openssl'

# Helpers da Fase CH: gateway de canais simulado (WebMock) e eventos assinados.
module ChannelsGatewayHelpers
  GATEWAY_URL = 'http://gateway.test'
  GATEWAY_TOKEN = 'gw-token-test'

  def with_gateway_env
    old = ENV.values_at('CHANNELS_GATEWAY_URL', 'CHANNELS_GATEWAY_TOKEN')
    ENV['CHANNELS_GATEWAY_URL'] = GATEWAY_URL
    ENV['CHANNELS_GATEWAY_TOKEN'] = GATEWAY_TOKEN
    yield
  ensure
    ENV['CHANNELS_GATEWAY_URL'], ENV['CHANNELS_GATEWAY_TOKEN'] = old
  end

  def gateway_url(path)
    "#{GATEWAY_URL}/internal/channels#{path}"
  end

  def signed_headers(secret, body, timestamp: Time.now.to_i, event_id: SecureRandom.uuid, signature: nil)
    sig = signature || "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")}"
    { 'X-Luar-Event-Id' => event_id, 'X-Luar-Timestamp' => timestamp.to_s, 'X-Luar-Signature' => sig,
      'CONTENT_TYPE' => 'application/json' }
  end

  def gateway_message_event(external_id: 'm-1', text: 'olá', direction: 'incoming', conversation: 'thread-1', **extra)
    {
      event_id: SecureRandom.uuid, type: 'message.created', account_id: 1, connection_id: SecureRandom.uuid,
      channel: 'instagram', provider_mode: 'experimental', occurred_at: Time.current.iso8601,
      conversation: { external_id: conversation, contact: { external_id: 'u-1', name: 'Maria', username: 'maria' } },
      message: { external_id: external_id, direction: direction, text: text, sent_at: Time.current.iso8601, attachments: [] }.merge(extra)
    }
  end
end

RSpec.configure { |c| c.include ChannelsGatewayHelpers }
