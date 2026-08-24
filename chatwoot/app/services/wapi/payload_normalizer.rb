class Wapi::PayloadNormalizer
  # Achado real 24/08/2026 (produto-09): os paths abaixo eram especulativos
  # (comentário original admitia "WAPI's real event taxonomy isn't stable/
  # public") -- confirmados agora contra o payload real de
  # `event: "webhookReceived"`:
  #   { event, instanceId, isGroup, fromMe, chat: {id},
  #     sender: {id, senderLid, pushName}, messageId,
  #     msgContent: {conversation, ...} }
  # Nenhum path especulativo antigo (`text`/`body`/`message.text`/
  # `data.message.conversation`) batia com nada disso -- por isso o job
  # sempre rodava sobre payload "vazio" (`message?` nunca true), silêncio
  # total, zero conversa chegando mesmo com o webhook confirmado em 200.
  def initialize(payload)
    @payload = payload.with_indifferent_access
  end

  def message?
    !from_me? && text.present? && sender_id.present? && message_id.present?
  end

  def connection_event?
    type.to_s.downcase.in?(%w[connected disconnected connection_update]) || payload.key?(:connected)
  end

  def connection_status
    truthy?(value_at(:connected, :status, [:data, :connected])) ? 'connected' : 'disconnected'
  end

  def message
    { from: sender_id, text: text, id: message_id, name: value_at([:sender, :pushName], :pushName, [:sender, :name]) }.compact
  end

  private

  attr_reader :payload

  # Sem isso, a resposta que o próprio agente manda pelo WhatsApp (fromMe:
  # true) voltaria pelo webhook e seria tratada como mensagem nova do
  # cliente -- eco infinito.
  def from_me? = truthy?(value_at(:fromMe))
  def type = value_at(:type, :event, :eventType)
  def sender_id = value_at([:sender, :id], :senderLid, :phone, :remoteJid, [:message, :from], [:data, :phone], [:data, :key, :remoteJid])
  def text = value_at([:msgContent, :conversation], :text, :body, [:message, :text], [:message, :body], [:data, :text], [:data, :message, :conversation], [:data, :message, :extendedTextMessage, :text])
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
