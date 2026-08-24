class Wapi::SendOnWapiService < Base::SendOnChannelService
  private

  def channel_class = Channel::Wapi

  # Achado real 24/08/2026 (produto-09, testado ao vivo): a mensagem saía de
  # verdade pro WhatsApp (confirmado recebendo no aparelho), mas o Chatwoot
  # nunca marcava como entregue -- ficava preso no relógio (pendente) pra
  # sempre. Faltava o que todo outro canal já faz no sucesso (Line/Facebook/
  # Instagram): `Messages::StatusUpdateService` pra 'delivered'.
  def perform_reply
    message_id = Wapi::Client.new(channel: channel).send_text(to: contact_inbox.source_id, text: message.outgoing_content)
    message.update!(source_id: message_id) if message_id.present?
    Messages::StatusUpdateService.new(message, 'delivered').perform
  rescue Wapi::Client::ApiError => e
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end
end
