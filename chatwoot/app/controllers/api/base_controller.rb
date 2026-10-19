class Api::BaseController < ApplicationController
  include AccessTokenAuthHelper
  respond_to :json
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :block_until_password_changed, unless: :authenticate_by_access_token?

  private

  # Senha provisória (spec 10): só o perfil fica liberado até a troca.
  def block_until_password_changed
    return unless current_user&.must_change_password?
    return if controller_path == 'api/v1/profiles'

    render json: { code: 'must_change_password', message: 'Troque a senha provisória para continuar' }, status: :forbidden
  end

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def check_authorization(model = nil)
    model ||= controller_name.classify.constantize

    authorize(model)
  end

  def check_admin_authorization?
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
