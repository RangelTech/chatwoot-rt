class Webhooks::EvolutionEventsJob < ApplicationJob
  queue_as :default

  def perform(instance_name:, params: {})
    channel = Channel::EvolutionApi.find_by(instance_name: instance_name)
    return unless channel

    case params[:event].to_s.upcase
    when 'CONNECTION_UPDATE'
      state = params.dig(:data, :state)
      channel.update!(connection_status: { 'state' => state, 'source' => 'webhook', 'checked_at' => Time.current.iso8601 },
                      connection_status_checked_at: Time.current, qr_code: state == 'open' ? nil : channel.qr_code)
    when 'MESSAGES_UPSERT'
      Evolution::IncomingMessageService.new(inbox: channel.inbox, params: params.with_indifferent_access).perform
    end
  end
end
