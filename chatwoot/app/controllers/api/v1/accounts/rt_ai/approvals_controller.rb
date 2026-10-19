# BFF das aprovações do Chat com IA (spec 10, U-2a). Quem decide é a própria pessoa, com a permissão
# `ai.approvals.decide`; o motor confere o dono da aprovação e devolve 404 para a de outra pessoa.
class Api::V1::Accounts::RtAi::ApprovalsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i
  DECISIONS = %w[approve deny].freeze

  before_action -> { require_permission('ai.chat.view') }, only: [:index]
  before_action -> { require_permission('ai.approvals.decide') }, only: [:decide]
  before_action :need_uuid, only: [:decide]

  # Pendentes do usuário (para o cartão reaparecer ao recarregar o chat).
  def index
    render_engine { Rt::EngineClient.get('/api/approvals/pending', claims: engine_context) }
  end

  def decide
    return render json: { code: 'invalid_decision', message: 'Decisão inválida' }, status: :unprocessable_entity unless DECISIONS.include?(params[:decision].to_s)

    render_engine { Rt::EngineClient.post("/api/approvals/#{params[:id]}", { decision: params[:decision].to_s }, claims: engine_context) }
  end

  private

  def render_engine
    render json: yield
  rescue Rt::EngineClient::Error => e
    case e.status
    when 404 then render json: { code: 'not_found', message: 'Aprovação não encontrada' }, status: :not_found
    when 409 then render json: { code: 'already_decided', message: 'Esta confirmação já foi respondida' }, status: :conflict
    else engine_failed(e)
    end
  end

  def need_uuid
    head :not_found unless UUID.match?(params[:id].to_s)
  end
end
