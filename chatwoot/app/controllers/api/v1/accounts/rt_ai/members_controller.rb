# Perfis de IA dos membros da Account (spec 10, U-1a). Só quem tem
# `ai.members.manage_roles` lista e altera; o perfil padrão vem do papel nativo.
class Api::V1::Accounts::RtAi::MembersController < Api::V1::Accounts::BaseController
  before_action :authorize_manage

  def index
    members = Current.account.account_users.includes(:user, :rt_ai_grant).map { |au| serialize(au) }
    render json: { roles: Rt::AiRoles::ROLES.keys, members: members }
  end

  def update
    account_user = Current.account.account_users.find(params[:id])
    role_key = params.require(:role_key)
    return render json: { error: 'invalid_role' }, status: :unprocessable_entity unless Rt::AiRoles::ROLES.key?(role_key)

    if role_key == Rt::AiRoles.default_key_for(account_user)
      account_user.rt_ai_grant&.destroy!
    else
      (account_user.rt_ai_grant || account_user.build_rt_ai_grant).update!(role_key: role_key)
    end
    render json: serialize(account_user.reload)
  end

  private

  def authorize_manage
    authorize :rt_ai_members, :update?, policy_class: Rt::AiMembersPolicy
  end

  def serialize(account_user)
    { id: account_user.id, user_id: account_user.user_id, name: account_user.user.name, email: account_user.user.email,
      role: account_user.role, ai_role_key: account_user.ai_role_key }
  end
end
