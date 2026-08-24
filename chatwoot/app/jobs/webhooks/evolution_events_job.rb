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
    when 'MESSAGES_UPDATE'
      process_message_update(channel, params)
    end
  end

  private

  # Status real do WhatsApp (protocolo Baileys, documentado):
  # PENDING/SERVER_ACK (mandou pro servidor) -> já é 'sent' desde o envio;
  # DELIVERY_ACK (chegou no aparelho) -> 'delivered'; READ/PLAYED (leu/ouviu)
  # -> 'read'. `fromMe: false` é status de mensagem QUE RECEBEMOS, não da
  # nossa própria saída -- não se aplica aqui, ignorado.
  def process_message_update(channel, params)
    data = params[:data] || {}
    return unless data[:fromMe]

    message_id = data[:messageId] || data.dig(:keyId)
    return if message_id.blank?

    message = channel.inbox.messages.find_by(source_id: message_id)
    return unless message

    status = case data[:status].to_s.upcase
             when 'READ', 'PLAYED' then 'read'
             when 'DELIVERY_ACK', 'DELIVERED' then 'delivered'
             else nil
             end
    return unless status

    Messages::StatusUpdateService.new(message, status).perform
  end
end
