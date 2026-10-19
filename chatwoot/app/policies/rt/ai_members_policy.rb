class Rt::AiMembersPolicy < Rt::AiPolicy
  VIEW = 'ai.members.manage_roles'.freeze
  MANAGE = 'ai.members.manage_roles'.freeze

  def update?
    allowed?(MANAGE)
  end
end
