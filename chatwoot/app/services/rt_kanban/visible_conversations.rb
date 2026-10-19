# Conversas que o operador pode ver no quadro: admin todas; agente as das suas caixas OU dos seus times.
# Nunca parte de Conversation.all: sempre da Account atual.
class RtKanban::VisibleConversations
  def self.call(account:, user:)
    scope = account.conversations
    account_user = account.account_users.find_by(user_id: user.id)
    return scope.none if account_user.nil?
    return scope if account_user.administrator?

    inbox_ids = user.inboxes.where(account_id: account.id).select(:id)
    team_ids = user.teams.where(account_id: account.id).select(:id)
    scope.where(inbox_id: inbox_ids).or(scope.where(team_id: team_ids)).distinct
  end
end
