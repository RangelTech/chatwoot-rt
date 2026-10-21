# Fase F-8: configuracao de filas pertence ao Chatwoot. O browser nunca envia
# account_id: toda consulta e escrita e limitada a Current.account.
class Api::V1::Accounts::RtAi::QueuesController < Api::V1::Accounts::RtAi::BaseController
  before_action -> { require_permission('ai.inbox_routing.view') }, only: :index
  before_action -> { require_permission('ai.inbox_routing.manage') }, except: [:index, :respondent]
  before_action :load_binding, only: [:update, :destroy]

  def index
    bindings = Rt::QueueBinding.where(account_id: Current.account.id).index_by(&:team_id)
    entries = Rt::InboxEntryQueue.where(account_id: Current.account.id).index_by(&:inbox_id)
    render json: {
      queues: Current.account.teams.order(:name).map { |team| queue_json(team, bindings[team.id]) },
      inboxes: Current.account.inboxes.order(:name).map { |inbox| inbox_json(inbox, entries[inbox.id]) }
    }
  end

  def create
    binding = nil
    ApplicationRecord.transaction do
      team = Current.account.teams.create!(team_attributes)
      binding = Rt::QueueBinding.create!(binding_attributes(team))
    end
    render json: queue_json(binding.team, binding), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { code: 'queue_rejected', message: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def update
    ApplicationRecord.transaction do
      @binding.team.update!(team_attributes)
      @binding.team.update!(allow_auto_assign: false) if queue_params[:respondent_kind] == 'ia'
      @binding.update!(binding_attributes(@binding.team))
    end
    render json: queue_json(@binding.team, @binding)
  rescue ActiveRecord::RecordInvalid => e
    render json: { code: 'queue_rejected', message: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def destroy
    destination_id = params[:destination_team_id].presence
    ApplicationRecord.transaction do
      @binding.team.rt_move_open_conversations_to = destination_id
      @binding.team.destroy!
      @binding.destroy!
    end
    head :no_content
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid => e
    messages = e.respond_to?(:record) ? e.record.errors.full_messages : [e.message]
    render json: { code: 'queue_not_removed', message: messages.to_sentence }, status: :unprocessable_entity
  end

  # Indicador do cabecalho da conversa (qualquer operador com acesso a conversa): so leitura, nunca aplica nada.
  def respondent
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    authorize conversation, :show?
    render json: Rt::Routing::RespondentView.call(conversation)
  rescue ActiveRecord::RecordNotFound
    render json: { code: 'not_found', message: 'Conversa não encontrada' }, status: :not_found
  end

  # Cada caixa tem seu proprio interruptor: legado, sombra ou filas, e uma
  # fila de entrada obrigatoria fora do legado. Isso permite volta imediata.
  def entry
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    record = Rt::InboxEntryQueue.find_or_initialize_by(inbox: inbox)
    record.assign_attributes(routing_mode: params.require(:routing_mode), team_id: params[:team_id].presence)
    record.save!
    render json: inbox_json(inbox, record)
  rescue ActiveRecord::RecordNotFound
    render json: { code: 'not_found', message: 'Caixa de entrada não encontrada' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { code: 'entry_rejected', message: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def load_binding
    @binding = Current.account.rt_queue_bindings.find_by!(team_id: params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { code: 'not_found', message: 'Fila não encontrada' }, status: :not_found
  end

  def queue_params
    params.permit(:name, :description, :respondent_kind, :template_id, :mode, destination_team_ids: [])
  end

  def team_attributes
    { name: queue_params[:name], description: queue_params[:description], allow_auto_assign: queue_params[:respondent_kind] != 'ia' }
  end

  def binding_attributes(team)
    {
      account: Current.account,
      team: team,
      respondent_kind: queue_params[:respondent_kind].presence || @binding&.respondent_kind || 'humano',
      template_id: queue_params[:template_id].presence,
      mode: queue_params[:mode].presence || 'desligado',
      description: queue_params[:description],
      allowed_destination_team_ids: Array(queue_params[:destination_team_ids]).filter_map(&:presence).map(&:to_i)
    }
  end

  def queue_json(team, binding)
    {
      id: team.id, name: team.name, description: team.description, member_count: team.team_members.count,
      allow_auto_assign: team.allow_auto_assign,
      respondent_kind: binding&.respondent_kind || 'humano', template_id: binding&.template_id,
      mode: binding&.mode || 'desligado', destination_team_ids: binding&.allowed_destination_team_ids || []
    }
  end

  def inbox_json(inbox, entry)
    { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, routing_mode: entry&.routing_mode || 'legado', entry_team_id: entry&.team_id }
  end
end
