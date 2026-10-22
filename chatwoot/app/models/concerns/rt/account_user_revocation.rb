# Remover a pessoa da empresa (AccountUser destruído, inclusive ao excluir o usuário) avisa o motor
# de IA pela fila (`member_revoked`): sessões e streams dela cortam em segundos. Quando é a Account
# inteira que está sendo excluída, quem cuida disso é o `deprovision`.
module Rt::AccountUserRevocation
  extend ActiveSupport::Concern

  prepended do
    after_destroy_commit :enqueue_member_revoked
  end

  private

  def enqueue_member_revoked
    return if destroyed_by_association&.active_record == Account || !Account.exists?(account_id)

    Rt::AccountLifecycle.enqueue(account_id, 'member_revoked', user_id: user_id)
  end
end
