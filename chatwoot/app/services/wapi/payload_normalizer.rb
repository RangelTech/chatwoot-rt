class Wapi::PayloadNormalizer
  def initialize(payload)
    @payload = payload.with_indifferent_access
  end

  def message?
    text.present? && sender_id.present? && message_id.present?
  end

  def connection_event?
    type.to_s.downcase.in?(%w[connected disconnected connection_update]) || payload.key?(:connected)
  end

  def connection_status
    truthy?(value_at(:connected, :status, [:data, :connected])) ? 'connected' : 'disconnected'
  end

  def message
    { from: sender_id, text: text, id: message_id, name: value_at(:pushName, [:sender, :name], [:data, :sender, :name]) }.compact
  end

  private

  attr_reader :payload

  def type = value_at(:type, :event, :eventType)
  def sender_id = value_at(:senderLid, :phone, :remoteJid, [:message, :from], [:sender, :phone], [:data, :phone], [:data, :key, :remoteJid])
  def text = value_at(:text, :body, [:message, :text], [:message, :body], [:data, :text], [:data, :message, :conversation], [:data, :message, :extendedTextMessage, :text])
  def message_id = value_at(:messageId, :id, [:message, :id], [:key, :id], [:data, :id], [:data, :key, :id])

  def value_at(*paths)
    paths.each do |path|
      value = payload.dig(*Array(path))
      return value if value.present?
    end
    nil
  end

  def truthy?(value)
    value == true || value.to_s.downcase.in?(%w[true connected open])
  end
end
