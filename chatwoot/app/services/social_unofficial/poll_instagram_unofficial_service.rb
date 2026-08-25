# Produto-10 (25/08/2026): sem webhook (credencial é sessão de cookie, não
# um app registrado com callback), então mensagem nova chega por polling
# periódico do inbox privado -- ver SocialUnofficial::InstagramClient pro
# porquê desse endpoint específico (testado ao vivo com cookies reais).
#
# `contact_inbox.source_id` guarda o thread_id (não o user_id) -- é o que
# SendOnInstagramUnofficialService precisa pra responder no thread certo.
class SocialUnofficial::PollInstagramUnofficialService
  pattr_initialize [:channel!]

  def perform
    resultado = channel.client.inbox
    (resultado.dig('inbox', 'threads') || []).each { |thread| processar_thread(thread) }
    channel.update!(last_polled_at: Time.current)
  rescue SocialUnofficial::InstagramClient::ApiError => e
    channel.update!(connection_status: { 'state' => 'error', 'error' => e.message })
  end

  private

  def processar_thread(thread)
    thread_id = thread['thread_id']
    outro_usuario = (thread['users'] || []).first
    return unless outro_usuario # grupo sem "outro" claro, ou thread vazia -- fora de escopo por ora

    (thread['items'] || []).each do |item|
      next unless item['item_type'] == 'text'
      next if item['is_sent_by_viewer']
      next if item['text'].blank?
      next if duplicate_message?(item['item_id'])

      criar_mensagem!(thread_id: thread_id, item: item, usuario: outro_usuario)
    end
  end

  def duplicate_message?(item_id)
    channel.inbox.messages.exists?(source_id: item_id)
  end

  def criar_mensagem!(thread_id:, item:, usuario:)
    contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: thread_id,
      inbox: channel.inbox,
      contact_attributes: { name: usuario['full_name'].presence || usuario['username'] }
    ).perform

    conversation = contact_inbox.conversations.where.not(status: :resolved).last ||
                   Conversation.create!(
                     account_id: channel.inbox.account_id,
                     inbox_id: channel.inbox.id,
                     contact_id: contact_inbox.contact_id,
                     contact_inbox_id: contact_inbox.id
                   )

    conversation.messages.create!(
      content: item['text'],
      account_id: channel.inbox.account_id,
      inbox_id: channel.inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      source_id: item['item_id']
    )
  end
end
