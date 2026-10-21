# Fase F (F-2/F-5/F-6): rotas internas da bridge. Auth: token de servico (RT_INTERNAL_TOKEN).
class RtInternal::RoutingController < ActionController::API
  before_action :authenticate_service
  before_action :load_conversation, except: :pending

  # GET /internal/routing/resolve?account_id=&conversation_id=&legacy=ia|humano
  def resolve
    render json: Rt::Routing::Resolve.call(@conversation, legacy: params[:legacy].presence)
  end

  # GET /internal/routing/destinations: filas de destino permitidas da fila atual (nome + descricao).
  def destinations
    binding = Rt::QueueBinding.find_by(team_id: @conversation.team_id)
    ids = Array(binding&.allowed_destination_team_ids)
    bindings = Rt::QueueBinding.where(team_id: ids).index_by(&:team_id)
    items = @conversation.account.teams.where(id: ids).order(:id).map do |team|
      { id: team.id, name: team.name, description: bindings[team.id]&.description.presence || team.description.to_s,
        respondent: bindings[team.id]&.respondent_kind || 'humano' }
    end
    render json: { queue_id: @conversation.team_id, destinations: items }
  end

  # POST /internal/routing/handoff {queue, summary, run_id}
  def handoff
    result = Rt::Routing::Handoff.call(conversation: @conversation, destination: params[:queue].presence,
                                       summary: params[:summary], run_id: params[:run_id].presence)
    render json: { ok: result.ok, reason: result.reason, team_id: result.team_id }, status: result.ok ? :ok : :unprocessable_entity
  end

  # GET /internal/routing/pending?minutes=15: conversas em modo filas, atendidas por IA, cuja ultima mensagem publica
  # e do cliente e nao teve resposta (ex.: a bridge reiniciou e o webhook se perdeu). Serve a varredura da bridge.
  def pending
    since = (params[:minutes].presence || 15).to_i.clamp(1, 120).minutes.ago
    entries = Rt::InboxEntryQueue.where(routing_mode: 'filas').includes(:inbox)
    items = entries.flat_map do |entry|
      Conversation.where(inbox_id: entry.inbox_id, status: %i[open pending]).where('last_activity_at >= ?', since).filter_map do |conv|
        last = conv.messages.where(private: false, message_type: %i[incoming outgoing]).order(:id).last
        next unless last&.incoming? && last.created_at >= since
        next unless Rt::Routing::RespondentView.call(conv)[:respondent] == 'ia'

        { account_id: conv.account_id, conversation_id: conv.display_id, inbox_id: conv.inbox_id,
          message: { id: last.id, content: last.content, message_type: 'incoming' } }
      end
    end
    render json: { items: items }
  end

  # GET /internal/routing/history
  def history
    render json: { conversation_id: @conversation.display_id, messages: Rt::Routing::History.call(@conversation) }
  end

  private

  def authenticate_service
    expected = ENV['RT_INTERNAL_TOKEN'].to_s
    given = request.headers['Authorization'].to_s.delete_prefix('Bearer ').strip
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    render json: { error: 'unauthorized' }, status: :unauthorized
  end

  def load_conversation
    account = Account.find_by(id: params[:account_id])
    @conversation = account&.conversations&.find_by(display_id: params[:conversation_id])
    render json: { error: 'not_found' }, status: :not_found unless @conversation
  end
end
