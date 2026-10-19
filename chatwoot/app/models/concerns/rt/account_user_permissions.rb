# Soma as permissões de IA (`ai.*`) ao que o Chatwoot já devolve em
# `AccountUser#permissions`. Não altera `administrator`/`agent`; só acrescenta.
module Rt::AccountUserPermissions
  extend ActiveSupport::Concern

  prepended do
    has_one :rt_ai_grant, class_name: 'Rt::AiGrant', dependent: :destroy
  end

  def permissions
    super + ai_permissions
  end

  def ai_role_key
    rt_ai_grant&.role_key || Rt::AiRoles.default_key_for(self)
  end

  def ai_permissions
    Rt::AiRoles.permissions_for(ai_role_key)
  end
end
