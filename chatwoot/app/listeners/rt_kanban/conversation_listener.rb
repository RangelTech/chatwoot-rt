# Novas conversas ganham cartão fora do ciclo da mensagem (listener assíncrono).
class RtKanban::ConversationListener < BaseListener
  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    board = RtKanban::Board.find_by(account_id: conversation.account_id)
    return unless board&.enabled

    RtKanban::EnsureCard.call(conversation)
  end
end
