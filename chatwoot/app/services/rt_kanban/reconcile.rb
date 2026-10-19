# Contagens por Account: conversas, cartões, faltando, duplicados e cruzados (deve ser tudo zero).
class RtKanban::Reconcile
  def self.call(account)
    cards = RtKanban::Card.where(account_id: account.id)
    {
      conversations: account.conversations.count,
      cards: cards.count,
      missing: account.conversations.where.not(id: cards.select(:conversation_id)).count,
      duplicate: cards.group(:conversation_id).having('count(*) > 1').count.size,
      cross_account: cards.joins(:conversation).where.not(conversations: { account_id: account.id }).count
    }
  end
end
