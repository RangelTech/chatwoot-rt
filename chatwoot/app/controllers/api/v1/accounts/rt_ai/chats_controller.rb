# BFF do Chat com IA (spec 10, U-2a). Rails valida Account + permissão `ai.*` e repassa ao motor com o
# contexto assinado; o navegador nunca recebe token de serviço nem escolhe tenant/usuário.
class Api::V1::Accounts::RtAi::ChatsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i

  before_action -> { require_permission('ai.chat.view') }, only: [:index, :messages, :templates]
  before_action -> { require_permission('ai.chat.run') }, only: [:stream_ticket, :cancel, :feedback]
  before_action :need_uuid, only: [:messages, :cancel, :feedback]

  def index
    data = engine_get('/api/chats')
    render json: data unless performed?
  end

  def messages
    data = engine_get("/api/chats/#{params[:id]}/messages")
    render json: data unless performed?
  end

  # Só agentes publicados (o seletor do chat); Factory e arquivados ficam de fora.
  def templates
    data = engine_get('/api/templates')
    return if performed?

    items = (data.is_a?(Array) ? data : data['items'] || []).select { |t| t['active_version_id'] || t['active_version'] }
    render json: items.reject { |t| t['system_key'].present? }
  end

  # Contexto assinado de uso único (≤ 60 s) que o navegador envia ao stream da mesma origem.
  def stream_ticket
    claims = engine_context(scopes: Current.account_user.permissions.grep(/\Aai\./))
    render json: { ticket: Rt::EngineClient.sign(claims), expires_in: Rt::EngineClient::TTL }
  end

  def cancel
    data = engine_post("/api/chat/runs/#{params[:id]}/cancel")
    render json: data unless performed?
  end

  def feedback
    data = engine_post("/api/chats/#{params[:id]}/feedback", params.permit(:rating, :comment).to_h)
    render json: data unless performed?
  end

  private

  def need_uuid
    head :not_found unless UUID.match?(params[:id].to_s)
  end
end
