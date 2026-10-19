# A exclusão da conversa grava o evento e remove o cartão na MESMA transação (auditoria estrutural).
module Rt::ConversationKanban
  extend ActiveSupport::Concern

  prepended do
    before_destroy { RtKanban::DeleteCard.call(self) }
  end
end
