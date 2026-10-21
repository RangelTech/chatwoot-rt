# BFF de cadastros de IA (spec 10, U-4): provedores, uso, execuções, ambiente e integrações.
# Credenciais (segredos, bancos, SSH, GCP, e-mail, pagamento, OAuth) vivem em CredentialsController.
# Allowlist fixa por domínio: nada de URL ou método vindos do navegador. Segredos só entram (write-only).
class Api::V1::Accounts::RtAi::ResourcesController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i

  RESOURCES = {
    'providers' => { gateway: :providers, view: 'ai.providers.view', manage: 'ai.providers.manage',
                     fields: %w[name provider model api_key api_base], item_actions: %w[test] },
    'combos' => { gateway: :combos, view: 'ai.providers.view', manage: 'ai.providers.manage', fields: %w[name models] },
    'quotas' => { gateway: :summary, view: 'ai.usage.view', manage: nil, fields: [] },
    'usage' => { gateway: :usage, view: 'ai.usage.view', manage: nil, fields: [] },
    'requests' => { gateway: :requests, view: 'ai.usage.view', manage: nil, fields: [] },
    'runs' => { path: '/api/hermes/sessions', view: 'ai.runs.view', manage: nil, fields: [] },
    'environment' => { path: '/api/environment', view: 'ai.environment.view', manage: 'ai.environment.manage', fields: [],
                       actions: %w[start stop backup] },
    'inboxes' => { path: '/api/omnichannel/inboxes', view: 'ai.inbox_routing.view', manage: 'ai.inbox_routing.manage',
                   fields: [], update_suffix: '/ia', update_fields: %w[template_id autopilot handoff_team_id show_progress] },
    'integrations' => { path: '/api/integrations', view: 'ai.integrations.view', manage: 'ai.integrations.manage',
                        fields: %w[name] }
  }.freeze

  before_action :find_resource
  before_action -> { require_permission(@rt_resource[:view]) }, only: [:index, :models]
  before_action -> { require_permission(@rt_resource[:manage].to_s) }, only: [:create, :update, :destroy, :action, :member_action]
  before_action :need_id, only: [:update, :destroy, :member_action, :models]

  def index
    return render_gateway(gateway_get) if @rt_resource[:gateway]

    render_engine engine_get(@rt_resource[:path])
  end

  def create
    return render_gateway(gateway_post) if @rt_resource[:gateway]

    body = params.permit(*@rt_resource[:fields]).to_h
    body['config'] = params[:config].to_unsafe_h if params[:config].respond_to?(:to_unsafe_h)
    render_engine engine_post(@rt_resource[:path], body)
  end

  # Lista de modelos de uma conexão. A identificação do tenant continua sendo
  # derivada de Current.account dentro de GatewayClient, e não da requisição.
  def models
    return head :not_found unless @rt_resource[:gateway] == :providers

    render_gateway Rt::GatewayClient.get(account: Current.account, path: "/api/providers/#{params[:id]}/models")
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  def update
    return render_gateway(gateway_put) if @rt_resource[:gateway]

    return head :not_found if @rt_resource[:update_fields].blank?

    path = "#{@rt_resource[:path]}/#{params[:id]}#{@rt_resource[:update_suffix]}"
    render_engine engine_put(path, params.permit(*@rt_resource[:update_fields]).to_h)
  end

  def destroy
    return render_gateway(gateway_delete) if @rt_resource[:gateway]

    render_engine engine_delete("#{@rt_resource[:path]}/#{params[:id]}")
  end

  def action
    return head :not_found unless Array(@rt_resource[:actions]).include?(params[:name])

    render_engine engine_post("#{@rt_resource[:path]}/#{params[:name]}")
  end

  # Acao por item (por exemplo, testar um provedor). A allowlist continua no
  # servidor e o id passa pelo formato restrito; o browser nao escolhe rota do Gateway.
  def member_action
    return head :not_found unless Array(@rt_resource[:item_actions]).include?(params[:name])

    return render_gateway(gateway_member_action) if @rt_resource[:gateway]

    head :not_found
  end

  private

  def find_resource
    @rt_resource = RESOURCES[params[:key]]
    head :not_found if @rt_resource.nil?
  end

  def render_engine(data)
    render json: data unless performed?
  end

  def render_gateway(data)
    render json: data unless performed?
  end

  def gateway_get
    case @rt_resource[:gateway]
    when :providers
      # A API do Gateway usa camelCase. Normalizamos somente o estado público
      # para a tabela Vue, sem expor campos de credencial ou alterar o escopo.
      (Rt::GatewayClient.get(account: Current.account, path: '/api/providers')['connections'] || []).map do |provider|
        provider.merge('is_active' => provider['isActive'])
      end
    when :combos then Rt::GatewayClient.get(account: Current.account, path: '/api/combos')['combos'] || []
    when :summary, :usage, :requests
      tenant_id = Rt::AiAccount.find_by!(account_id: Current.account.id).engine_tenant_id
      suffix = { summary: 'summary', usage: 'usage', requests: 'requests?limit=50' }.fetch(@rt_resource[:gateway])
      Rt::GatewayClient.get(account: Current.account, path: "/api/tenants/#{tenant_id}/#{suffix}")
    end
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  def gateway_post
    body = params.permit(*@rt_resource[:fields], models: []).to_h
    case @rt_resource[:gateway]
    when :providers
      Rt::GatewayClient.post(account: Current.account, path: '/api/providers', payload: {
                               name: body['name'], provider: body['provider'], apiKey: body['api_key'], defaultModel: body['model']
                             }.compact)['connection']
    when :combos
      payload = combo_payload
      return if performed?

      Rt::GatewayClient.post(account: Current.account, path: '/api/combos', payload: payload)
    end
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  def gateway_put
    body = params.permit(:name, :model, :api_key, :is_active, models: []).to_h
    if @rt_resource[:gateway] == :providers
      payload = { name: body['name'], apiKey: body['api_key'], defaultModel: body['model'], isActive: body['is_active'] }.compact
    else
      payload = combo_payload
      return if performed?
    end
    Rt::GatewayClient.put(account: Current.account, path: "/api/#{@rt_resource[:gateway]}/#{params[:id]}", payload: payload)
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  COMBO_NAME = /\A[\w .\-]{1,64}\z/
  COMBO_MODEL = %r{\A[\w.\-:/ ]{1,128}\z}
  COMBO_STRATEGIES = %w[fallback round-robin fusion].freeze

  # Combo do tenant: só nomes/modelos em texto simples e estratégia da lista. Quais provedores/combos
  # existem é decidido pelo gateway (400 para provedor de outro tenant); o BFF só filtra a forma.
  def combo_payload
    name = params[:name].to_s
    models = Array(params[:models]).map(&:to_s)
    strategy = params[:strategy].respond_to?(:permit) ? params[:strategy].permit(:fallbackStrategy, :judgeModel).to_h : {}
    invalid = name.present? && !COMBO_NAME.match?(name)
    invalid ||= models.size > 30 || models.any? { |m| !COMBO_MODEL.match?(m) }
    invalid ||= strategy['fallbackStrategy'].present? && COMBO_STRATEGIES.exclude?(strategy['fallbackStrategy'])
    if invalid
      render json: { code: 'invalid_combo', message: 'Combo inválido' }, status: :unprocessable_entity
      return nil
    end

    { name: name.presence, models: (models if params.key?(:models)), strategy: strategy.presence }.compact
  end

  def gateway_delete
    Rt::GatewayClient.delete(account: Current.account, path: "/api/#{@rt_resource[:gateway]}/#{params[:id]}")
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  def gateway_member_action
    case [@rt_resource[:gateway], params[:name]]
    when [:providers, 'test']
      Rt::GatewayClient.post(account: Current.account, path: "/api/providers/#{params[:id]}/test")
    end
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  # Erro de validação do gateway (ex.: provedor que o tenant não tem) é texto de negócio, sem segredo.
  def gateway_message(error)
    text = error.body.is_a?(Hash) ? error.body['error'] : nil
    text.is_a?(String) ? text.first(300) : nil
  end

  def gateway_failed(error)
    Rails.logger.warn("rt_ai gateway error: #{error.message}")
    status = PASSTHROUGH_STATUSES.include?(error.status) ? error.status : :bad_gateway
    message = gateway_message(error) if status != :bad_gateway
    render json: { code: 'gateway_error', message: message || 'Gateway de IA indisponível no momento' }, status: status
    nil
  end

  def need_id
    head :not_found unless UUID.match?(params[:id].to_s) || params[:id].to_s.match?(/\A\d{1,10}\z/)
  end
end
