# Produto-05 (25-26/08/2026, madrugada): mesmo desenho do
# PollInstagramUnofficialService, mas com uma diferença real de
# fidelidade -- o Facebook não tem API HTTP não-oficial (SPA JS-only,
# ver NavegadorRemotoService), então `/facebook/inbox` só devolve o
# **snippet** da última mensagem por thread (o que dá pra ler do DOM da
# lista de conversas sem abrir cada thread individualmente), não o
# histórico mensagem-a-mensagem com remetente que o Instagram tem via
# API real. Abrir cada thread e ler o DOM de cada bolha exigiria
# seletores que ninguém validou contra Facebook real ainda (diferente
# do `/facebook/inbox`, que já foi confirmado 25/08 com cookie real do
# dono) -- fica registrado como melhoria futura, não implementado às
# cegas aqui.
#
# Por isso o dedup usa o snippet como fingerprint (`thread_id:snippet`)
# em vez de um id de mensagem real, e a proteção de eco compara contra o
# conteúdo da ÚLTIMA mensagem da conversa (de qualquer tipo) -- se
# baterem, é o próprio snippet refletindo algo que o Chatwoot acabou de
# mandar (via SendOnFacebookUnofficialService), não uma mensagem nova.
class SocialUnofficial::PollFacebookUnofficialService
  pattr_initialize [:channel!]

  def perform
    conversas = SocialUnofficial::NavegadorRemotoService.new(provider: 'facebook_web')
                                                          .facebook_inbox(cookies: channel.cookies_jar)
    conversas.each { |thread| processar_thread(thread) }
    channel.update!(last_polled_at: Time.current)
  rescue SocialUnofficial::NavegadorRemotoService::NavegadorRemotoError => e
    channel.update!(connection_status: { 'state' => 'error', 'error' => e.message })
  end

  private

  def processar_thread(thread)
    thread_id = thread['thread_id']
    snippet = thread['snippet'].to_s.strip
    return if thread_id.blank? || snippet.blank?
    return if duplicate_snippet?(thread_id: thread_id, snippet: snippet)

    criar_mensagem!(thread: thread, snippet: snippet)
  end

  def duplicate_snippet?(thread_id:, snippet:)
    fingerprint = Digest::SHA256.hexdigest("#{thread_id}:#{snippet}")
    channel.inbox.messages.exists?(source_id: fingerprint)
  end

  def criar_mensagem!(thread:, snippet:)
    thread_id = thread['thread_id']
    contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: thread_id,
      inbox: channel.inbox,
      contact_attributes: { name: thread['name'].presence || thread_id }
    ).perform

    conversation = contact_inbox.conversations.where.not(status: :resolved).last ||
                   Conversation.create!(
                     account_id: channel.inbox.account_id,
                     inbox_id: channel.inbox.id,
                     contact_id: contact_inbox.contact_id,
                     contact_inbox_id: contact_inbox.id
                   )

    # Proteção de eco: se a última mensagem da conversa (qualquer tipo) já
    # tem esse texto, é o snippet refletindo o que o Chatwoot acabou de
    # mandar -- não cria duplicata como se fosse resposta nova do contato.
    return if conversation.messages.order(created_at: :desc).first&.content == snippet

    conversation.messages.create!(
      content: snippet,
      account_id: channel.inbox.account_id,
      inbox_id: channel.inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      source_id: Digest::SHA256.hexdigest("#{thread_id}:#{snippet}")
    )
  end
end
