# BFF do assistente "Conectar canal" (Fase CH): somente administradores da conta.
class ChannelConnectionPolicy < ApplicationPolicy
  def manage?
    account_user.present? && account_user.administrator?
  end

  alias catalog? manage?
  alias create? manage?
  alias show? manage?
  alias step? manage?
  alias cancel? manage?
  alias disconnect? manage?
  alias revoke? manage?
  alias reauth? manage?
  alias finalize? manage?
end
