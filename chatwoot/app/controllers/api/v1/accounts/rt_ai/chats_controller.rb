# BFF do Chat com IA (spec 10, U-2a). Rails valida Account + permissão `ai.*` e repassa ao motor com o
# contexto assinado; o navegador nunca recebe token de serviço nem escolhe tenant/usuário.
class Api::V1::Accounts::RtAi::ChatsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i

  before_action -> { require_permission('ai.chat.view') }, only: [:index, :messages, :templates, :artifacts, :artifact_download]
  before_action -> { require_permission('ai.chat.run') }, only: [:stream_ticket, :cancel, :feedback]
  before_action :need_uuid, only: [:messages, :cancel, :feedback, :artifacts, :artifact_download]
  before_action :need_artifact_uuid, only: [:artifact_download]

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
    # Spec 11 §23: o Sr Moon aparece primeiro, só para quem tem `ai.moon.use`; demais templates de sistema ficam de fora.
    moon_ok = Current.account_user.permissions.include?('ai.moon.use')
    items = items.select { |t| t['system_key'].blank? || (t['system_key'] == 'moon' && moon_ok) }
    render json: items.sort_by { |t| t['system_key'] == 'moon' ? 0 : 1 }
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

  # O motor exige `message_id` (a mensagem avaliada) e `rating` inteiro (-1 ou 1).
  def feedback
    payload = params.permit(:message_id, :comment).to_h
    payload['rating'] = params[:rating].to_i
    data = engine_post("/api/chats/#{params[:id]}/feedback", payload)
    render json: data unless performed?
  end

  # Arquivos gerados no chat. O motor só lista se a conversa for do próprio usuário (senão 404).
  def artifacts
    items = chat_artifacts
    render json: items.map { |a| a.merge('id' => a['artifact_id']) } unless performed?
  end

  # Download pela URL curta do BFF: o arquivo precisa estar na lista do chat do usuário (cobre a
  # checagem de dono que a rota de artefato do motor, sozinha, não faz). `inline=1` só para imagem.
  def artifact_download
    item = chat_artifacts.find { |a| a['artifact_id'].to_s == params[:artifact_id] }
    return if performed?
    return head :not_found unless item

    send_artifact(item)
  rescue Rt::EngineClient::Error => e
    e.status == 404 ? head(:not_found) : engine_failed(e)
  end

  SAFE_INLINE = %w[image/png image/jpeg image/gif image/webp].freeze

  private

  def chat_artifacts
    data = Rt::EngineClient.get("/api/chats/#{params[:id]}/artifacts", claims: engine_context)
    data.is_a?(Array) ? data : []
  rescue Rt::EngineClient::Error => e
    e.status == 404 ? head(:not_found) : engine_failed(e)
    []
  end

  def send_artifact(item)
    file = Rt::EngineClient.download("/api/artifacts/#{item['artifact_id']}/download", claims: engine_context)
    inline = params[:inline].present? && SAFE_INLINE.include?(file[:content_type])
    response.set_header('X-Content-Type-Options', 'nosniff')
    send_data file[:body], filename: download_name(item), type: file[:content_type], disposition: inline ? 'inline' : 'attachment'
  end

  def download_name(item)
    name = File.basename(item['title'].to_s.tr('\\', '/')).gsub(/[[:cntrl:]]/, '').strip
    name.presence || "arquivo-#{item['artifact_id']}"
  end

  def need_artifact_uuid
    head :not_found unless UUID.match?(params[:artifact_id].to_s)
  end

  def need_uuid
    head :not_found unless UUID.match?(params[:id].to_s)
  end
end
