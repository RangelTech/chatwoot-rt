# Produto-10 (25/08/2026): manda a resposta do agente pro Instagram real,
# via sessão de cookies capturada no login guiado. `contact_inbox.source_id`
# guarda o thread_id do Instagram (setado por
# SocialUnofficial::PollInstagramUnofficialService quando a conversa nasce
# de uma mensagem recebida).
class SocialUnofficial::SendOnInstagramUnofficialService
  pattr_initialize [:message!]

  def perform
    return if message.private?
    return unless message.outgoing?

    channel.client.send_text(thread_id: thread_id, text: message.content)
  rescue SocialUnofficial::InstagramClient::ApiError => e
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end

  private

  def channel
    @channel ||= message.conversation.inbox.channel
  end

  def thread_id
    message.conversation.contact_inbox.source_id
  end
end
