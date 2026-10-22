# Saída dos canais não oficiais (instagram/messenger/whatsapp/tiktok): chama o gateway
# POST /connections/:id/send com idempotency_key = message.id, de forma síncrona.
# Falha marca a mensagem como failed (sem retry silencioso que duplicaria).
class Channels::SendOnUnofficialService < Base::SendOnChannelService
  private

  def channel_class = channel.class

  def validate_target_channel
    raise 'Invalid channel service was called' unless channel.is_a?(UnofficialGatewayChannel)
  end

  def perform_reply
    return fail_message('channel_not_connected') unless channel.connected? && channel.connection_id.present?

    result = Channels::GatewayClient.new(account_id: channel.account_id).send_message(
      channel.connection_id,
      idempotency_key: message.id,
      conversation_ref: contact_inbox.source_id,
      text: message.outgoing_content,
      attachments: attachments_payload,
      reply_to: message.content_attributes['in_reply_to_external_id'].presence
    )
    apply_result(result)
  rescue Channels::GatewayClient::Error => e
    fail_message(e.code)
  end

  def apply_result(result)
    return fail_message(result[:error_code] || 'send_failed') if result[:status] == 'failed'

    message.update!(source_id: result[:external_id]) if result[:external_id].present?
    Messages::StatusUpdateService.new(message, 'delivered').perform if result[:status] == 'sent'
  end

  def fail_message(code)
    Messages::StatusUpdateService.new(message, 'failed', code).perform
  end

  def attachments_payload
    message.attachments.map do |a|
      { kind: a.file_type.to_s, mime: a.file&.content_type, name: a.file&.filename.to_s, url: a.download_url }
    end
  end
end
