class Evolution::SendOnEvolutionService < Base::SendOnChannelService
  private

  def channel_class = Channel::EvolutionApi

  def perform_reply
    message_id = Evolution::Client.new(channel: channel).send_text(
      to: contact_inbox.source_id,
      text: message.outgoing_content
    )
    message.update!(source_id: message_id) if message_id.present?
  rescue Evolution::Client::ApiError => e
    message.update!(external_error: e.message, status: :failed)
  end
end
