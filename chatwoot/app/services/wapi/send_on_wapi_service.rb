class Wapi::SendOnWapiService < Base::SendOnChannelService
  private

  def channel_class = Channel::Wapi

  def perform_reply
    message_id = Wapi::Client.new(channel: channel).send_text(to: contact_inbox.source_id, text: message.outgoing_content)
    message.update!(source_id: message_id) if message_id.present?
  rescue Wapi::Client::ApiError => e
    message.update!(external_error: e.message, status: :failed)
  end
end
