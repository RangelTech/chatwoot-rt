# Perfis de IA da Account (spec 10, U-1a). As permissões `ai.*` seguem o mesmo
# formato de string que o front e as policies já usam para `administrator` e
# `agent`; elas apenas se somam ao que `AccountUser#permissions` devolve.
module Rt::AiRoles
  ALL = %w[
    ai.chat.view ai.chat.run
    ai.agents.view ai.agents.create ai.agents.edit ai.agents.publish ai.agents.archive
    ai.skills.view ai.skills.manage_company ai.skills.manage_own
    ai.knowledge.view ai.knowledge.manage ai.memories.review
    ai.routines.view ai.routines.manage
    ai.runs.view ai.approvals.decide ai.usage.view
    ai.providers.view ai.providers.manage
    ai.credentials.view ai.credentials.manage
    ai.integrations.view ai.integrations.manage
    ai.payments.view ai.payments.manage
    ai.environment.view ai.environment.manage
    ai.inbox_routing.view ai.inbox_routing.manage
    ai.members.manage_roles
  ].freeze

  GESTOR = (ALL - %w[
    ai.providers.manage ai.credentials.manage ai.integrations.view ai.integrations.manage
    ai.payments.manage ai.environment.manage ai.inbox_routing.manage ai.members.manage_roles
  ]).freeze

  OPERADOR = %w[
    ai.chat.view ai.chat.run ai.agents.view ai.skills.view ai.skills.manage_own
    ai.knowledge.view ai.routines.view ai.runs.view ai.approvals.decide
  ].freeze

  LEITOR = %w[
    ai.chat.view ai.agents.view ai.skills.view ai.knowledge.view ai.routines.view ai.usage.view
  ].freeze

  ROLES = {
    'administrador_ia' => ALL,
    'gestor' => GESTOR,
    'operador' => OPERADOR,
    'leitor' => LEITOR
  }.freeze

  DEFAULT_FOR_ROLE = { 'administrator' => 'administrador_ia', 'agent' => 'operador' }.freeze

  def self.permissions_for(role_key)
    ROLES.fetch(role_key, [])
  end

  def self.default_key_for(account_user)
    DEFAULT_FOR_ROLE.fetch(account_user.role)
  end
end
