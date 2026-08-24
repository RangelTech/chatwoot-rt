class Evolution::SendOnEvolutionService < Base::SendOnChannelService
  private

  def channel_class = Channel::EvolutionApi

  # Mesmo achado do WAPI (produto-09, 24/08/2026): faltava marcar como
  # entregue no sucesso -- ver send_on_wapi_service.rb pro detalhe.
  def perform_reply
    message_id = Evolution::Client.new(channel: channel).send_text(
      to: contact_inbox.source_id,
      text: message.outgoing_content
    )
    message.update!(source_id: message_id) if message_id.present?
    Messages::StatusUpdateService.new(message, 'delivered').perform
  rescue Evolution::Client::ApiError => e
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end
end
