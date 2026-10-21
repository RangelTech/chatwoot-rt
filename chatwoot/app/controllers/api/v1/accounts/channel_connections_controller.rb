# BFF do assistente "Conectar canal" (Fase CH, docs/canais/CONTRATO_GATEWAY.md).
# Navegador -> Rails -> gateway, tudo síncrono: senha e códigos passam só pela requisição
# em andamento (nunca por job/Sidekiq) e não são gravados nem logados (filter_parameters).
class Api::V1::Accounts::ChannelConnectionsController < Api::V1::Accounts::BaseController
  before_action :authorize_manage
  before_action :ensure_gateway_configured
  before_action :validate_provider, only: [:create]

  rescue_from Channels::GatewayClient::Error, with: :render_gateway_error

  def catalog
    render json: gateway.catalog
  end

  def create
    return render json: { error_code: 'consent_required' }, status: :unprocessable_entity unless consent_given?

    consent = { accepted: true, version: params[:consent_version].presence || catalog_risk_version }
    result = gateway.create_connection(account_id: Current.account.id, provider: params[:provider], actor_id: Current.user.id,
                                       consent: consent, login_flow: params[:login_flow])
    render_result(result, status: :created)
  end

  def show
    render_result(gateway.show(params[:id]))
  end

  def step
    result = gateway.step(params[:id], step_id: params.require(:step_id).to_s, kind: params.require(:kind).to_s, data: step_data)
    render_result(result)
  end

  %i[cancel disconnect revoke reauth].each do |action|
    define_method(action) do
      result = gateway.public_send(action, params[:id])
      sync_channel_state(result)
      render_result(result)
    end
  end

  def finalize
    result = gateway.show(params[:id])
    connection = ensure_own_connection!(result)
    return render json: { error_code: 'not_connected' }, status: :unprocessable_entity unless connection[:state] == 'connected'

    existing = find_channel(params[:id])
    inbox = existing&.inbox || create_inbox_for(connection)
    render json: { inbox: inbox_json(inbox) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error_code: 'invalid', message: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def authorize_manage
    authorize :channel_connection, :manage?
  end

  def ensure_gateway_configured
    render json: { error_code: 'provider_unavailable' }, status: :service_unavailable unless Channels::GatewayClient.configured?
  end

  def validate_provider
    return if UnofficialGatewayChannel::PROVIDERS.key?(params[:provider].to_s)

    render json: { error_code: 'unsupported_provider' }, status: :unprocessable_entity
  end

  def gateway
    @gateway ||= Channels::GatewayClient.new(account_id: Current.account.id)
  end

  def consent_given?
    ActiveModel::Type::Boolean.new.cast(params[:consent]) == true
  end

  def catalog_risk_version
    gateway.catalog[:risk_notice_version]
  rescue Channels::GatewayClient::Error
    nil
  end

  # `data` carrega usuário/senha/código: só repassa os campos escalares, sem logar.
  def step_data
    raw = params[:data]
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.transform_values { |v| v.is_a?(Hash) || v.is_a?(Array) ? nil : v.to_s }.compact : {}
  end

  # Defesa em profundidade: o gateway já responde 404 para outro tenant; aqui checamos de novo.
  def ensure_own_connection!(result, strict: true)
    connection = result[:connection] || result
    return connection if !strict && connection[:account_id].blank?
    raise Channels::GatewayClient::Error.new(404, 'not_found') if connection[:account_id].to_i != Current.account.id

    connection
  end

  # StepView do gateway ({state, step}) não traz account_id: o isolamento ali é do gateway (404).
  def render_result(result, status: :ok)
    connection = ensure_own_connection!(result, strict: false)
    connection = { id: params[:id], state: result[:state] }.compact if result[:connection].nil? && connection[:account_id].blank?
    render json: { connection: connection, step: result[:step] }.compact, status: status
  end

  def render_gateway_error(error)
    status = case error.status
             when 404 then :not_found
             when 429 then :too_many_requests
             when 400..499 then :unprocessable_entity
             else :bad_gateway
             end
    render json: { error_code: error.code }, status: status
  end

  def find_channel(connection_id)
    UnofficialGatewayChannel::CHANNEL_TYPES.each_value do |name|
      channel = name.constantize.find_by(account_id: Current.account.id, connection_id: connection_id)
      return channel if channel
    end
    nil
  end

  # Estados do canal acompanham o que o gateway devolve (desconectar/revogar/reconectar).
  def sync_channel_state(result)
    connection = result[:connection] || result
    channel = find_channel(connection[:id])
    channel&.apply_connection_state!(connection[:state].to_s, error_code: connection[:last_error_code])
  end

  def create_inbox_for(connection)
    klass = UnofficialGatewayChannel.channel_class_for_provider(connection[:provider])
    channel = nil
    inbox = nil
    ActiveRecord::Base.transaction do
      channel = klass.new(account_id: Current.account.id, connection_id: connection[:id], state: 'connected',
                          external_label: connection[:external_label], connector_version: connection[:connector_version],
                          last_activity_at: Time.current)
      channel.generate_webhook_secret!
      channel.save!
      inbox = Current.account.inboxes.create!(name: params[:name].presence || channel.name, channel: channel)
      attach_agent_bot(inbox)
      register_delivery(channel, inbox)
    end
    start_sync(channel)
    inbox
  end

  def register_delivery(channel, inbox)
    gateway.delivery(channel.connection_id, webhook_url: channel.callback_url, webhook_secret: channel.webhook_secret, inbox_ref: inbox.id.to_s)
  end

  def start_sync(channel)
    gateway.sync(channel.connection_id, since_days: params[:sync_since_days].presence&.to_i || 60)
  rescue Channels::GatewayClient::Error => e
    Rails.logger.warn("channels sync not started: #{e.code}")
  end

  def attach_agent_bot(inbox)
    return if params[:agent_bot_id].blank?

    bot = AgentBot.accessible_to(Current.account).find(params[:agent_bot_id])
    AgentBotInbox.create!(inbox: inbox, agent_bot: bot)
  end

  def inbox_json(inbox)
    { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type, account_id: inbox.account_id,
      channel_id: inbox.channel_id, connection_id: inbox.channel.connection_id, state: inbox.channel.state }
  end
end
