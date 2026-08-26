# Produto-05 (25-26/08/2026, madrugada): espelha SendOnInstagramUnofficialService,
# mas via UI automation (Playwright, `/facebook/send` do oauth-browser) em
# vez de API HTTP direta -- Facebook não tem uma que funcione (ver
# NavegadorRemotoService). `contact_inbox.source_id` guarda o thread_id do
# Messenger (setado por PollFacebookUnofficialService quando a conversa
# nasce de uma mensagem recebida).
#
# NUNCA testado com contato real ainda (mesma ressalva já registrada no
# endpoint `/facebook/send` do oauth-browser) -- fica pendente validação
# com o dono presente antes de considerar esta ponta fechada de verdade.
class SocialUnofficial::SendOnFacebookUnofficialService
  pattr_initialize [:message!]

  def perform
    return if message.private?
    return unless message.outgoing?

    SocialUnofficial::NavegadorRemotoService.new(provider: 'facebook_web').facebook_send(
      cookies: channel.cookies_jar,
      thread_id: thread_id,
      text: message.content
    )
  rescue SocialUnofficial::NavegadorRemotoService::NavegadorRemotoError => e
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
