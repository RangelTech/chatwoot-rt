# Base das policies de IA: decide só pelas strings `ai.*` de `account_user.permissions`.
class Rt::AiPolicy < ApplicationPolicy
  def allowed?(permission)
    account_user.present? && account_user.permissions.include?(permission)
  end

  def index?
    allowed?(self.class::VIEW)
  end

  def show?
    index?
  end

  def create?
    allowed?(self.class::MANAGE)
  end
end
