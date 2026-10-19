# Cria os cartões das conversas existentes em lotes (retomável: só toca quem ainda não tem cartão).
class RtKanban::BackfillJob < ApplicationJob
  queue_as :low
  BATCH = 500

  def perform(account_id)
    account = Account.find(account_id)
    RtKanban::EnsureBoard.call(account)
    account.conversations.where.not(id: RtKanban::Card.where(account_id: account.id).select(:conversation_id))
           .find_each(batch_size: BATCH) { |conversation| RtKanban::EnsureCard.call(conversation, source: 'migration') }
  end
end
