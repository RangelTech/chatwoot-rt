class Webhooks::WapiEventsJob < ApplicationJob
  queue_as :default

  # WAPI's real event taxonomy isn't stable/public; we only act on the two
  # shapes the spec cares about — inbound message, and connection status change
  # (used to keep the health indicator fresh without polling).
  def perform(project_id:, params: {})
    @channel = Channel::Wapi.find_by(project_id: project_id)
    return unless @channel

    payload = Wapi::PayloadNormalizer.new(params)
    if payload.connection_event?
      process_connection_event(payload)
    elsif payload.message?
      Wapi::IncomingMessageService.new(inbox: @channel.inbox, params: payload.message.with_indifferent_access).perform
    end
  end

  private

  def process_connection_event(payload)
    status = payload.connection_status
    @channel.update!(
      connection_status: { 'status' => status, 'source' => 'webhook', 'checked_at' => Time.current.iso8601 },
      connection_status_checked_at: Time.current
    )
  end
end
