# Base do BFF de IA (spec 10, U-1e): membership e permissão `ai.*` pelo mecanismo
# do Chatwoot; o motor recebe só o contexto assinado, nunca tenant/usuário do corpo.
class Api::V1::Accounts::RtAi::BaseController < Api::V1::Accounts::BaseController
  before_action :require_ai_account

  private

  def require_ai_account
    ai = Rt::AiAccount.find_by(account_id: Current.account.id)
    return if ai&.ai_state == 'active' && ai.effective_flags['ai_enabled']

    render json: { code: 'ai_unavailable', message: 'IA indisponível nesta conta' }, status: :forbidden
  end

  def require_permission(permission)
    return if Current.account_user&.permissions&.include?(permission)

    render json: { code: 'forbidden', message: 'Permissão negada' }, status: :forbidden
  end

  def engine_context(scopes: nil)
    Rt::EngineClient.ui_context(account: Current.account, user: Current.user, account_user: Current.account_user, scopes: scopes)
  end

  def engine_get(path)
    Rt::EngineClient.get(path, claims: engine_context)
  rescue Rt::EngineClient::Error => e
    engine_failed(e)
  end

  def engine_post(path, payload = {})
    Rt::EngineClient.post(path, payload, claims: engine_context)
  rescue Rt::EngineClient::Error => e
    engine_failed(e)
  end

  def engine_put(path, payload = {})
    Rt::EngineClient.put(path, payload, claims: engine_context)
  rescue Rt::EngineClient::Error => e
    engine_failed(e)
  end

  def engine_delete(path)
    Rt::EngineClient.delete(path, claims: engine_context)
  rescue Rt::EngineClient::Error => e
    engine_failed(e)
  end

  # Erro de negócio do motor (400-499, exceto 401/403 de credencial do BFF) chega ao usuário com o status
  # e a mensagem dele; o resto (rede, 5xx, contexto recusado) vira 502 genérico.
  PASSTHROUGH_STATUSES = [400, 404, 409, 422].freeze

  def engine_failed(error)
    Rails.logger.warn("rt_ai engine error: #{error.message}")
    if PASSTHROUGH_STATUSES.include?(error.status) && error.detail.present?
      render json: { code: 'engine_rejected', message: error.detail }, status: error.status
    else
      render json: { code: 'engine_error', message: 'Serviço de IA indisponível no momento' }, status: :bad_gateway
    end
    nil
  end
end
