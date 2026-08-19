class Webhooks::WapiEventsJob < ApplicationJob
  queue_as :default

  # WAPI's real event taxonomy isn't stable/public; we only act on the two
  # shapes the spec cares about — inbound message, and connection status change
  # (used to keep the health indicator fresh without polling).
  def perform(project_id:, params: {})
    @channel = Channel::Wapi.find_by(project_id: project_id)
    return unless @channel

    if connection_event?(params)
      process_connection_event(params)
    elsif message_event?(params)
      Wapi::IncomingMessageService.new(inbox: @channel.inbox, params: params[:message].with_indifferent_access).perform
    end
  end

  private

  def message_event?(params)
    params[:type] == 'message' && params[:message].present?
  end

  def connection_event?(params)
    params[:type] == 'connection_update'
  end

  def process_connection_event(params)
    status = %w[true connected CONNECTED open OPEN].include?(params[:status]) ? 'connected' : 'disconnected'
    @channel.update!(
      connection_status: { 'status' => status, 'source' => 'webhook', 'checked_at' => Time.current.iso8601 },
      connection_status_checked_at: Time.current
    )
  end
end
