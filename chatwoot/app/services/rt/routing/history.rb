# Fase F (F-6): historico completo da conversa para o agente que a recebe. Notas privadas (de humanos ou do
# resumo da IA) entram marcadas como internas: o agente as usa como contexto e nunca as repete ao cliente.
class Rt::Routing::History
  INTERNAL_TAG = 'nota interna - nao repetir ao cliente'.freeze
  DEFAULT_LIMIT = 200

  def self.call(conversation, limit: DEFAULT_LIMIT)
    scope = conversation.messages.where(message_type: [:incoming, :outgoing]).order(:created_at, :id)
    scope = scope.where(id: scope.last(limit).map(&:id)) if scope.count > limit
    scope.includes(:sender).map { |message| entry(message) }
  end

  def self.entry(message)
    {
      id: message.id,
      at: message.created_at.iso8601,
      role: role(message),
      internal: message.private?,
      tag: message.private? ? INTERNAL_TAG : nil,
      agent: message.content_attributes.to_h['rt_agent'],
      content: message.content.to_s
    }
  end

  def self.role(message)
    return 'cliente' if message.incoming?
    return 'nota_interna' if message.private?
    return 'ia' if message.content_attributes.to_h['rt_origin'] == 'ia'

    'atendente'
  end
end
