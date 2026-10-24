# BFF de cadastros de IA (spec 10, U-4): provedores, uso, execuções, ambiente e integrações.
# Credenciais (segredos, bancos, SSH, GCP, e-mail, pagamento, OAuth) vivem em CredentialsController.
# Allowlist fixa por domínio: nada de URL ou método vindos do navegador. Segredos só entram (write-only).
class Api::V1::Accounts::RtAi::ResourcesController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i
  SERVICE_NAME = /\A[a-z][a-z0-9_-]{0,30}\z/
  SERVICE_ACTIONS = %w[start stop restart].freeze
  PROVIDER_BATCH_MODES = %w[provider oauth free apikey compatible all].freeze
  PROVIDER_ID = /\A[a-z0-9][a-z0-9_-]{0,80}\z/

  RESOURCES = {
    'providers' => { gateway: :providers, view: 'ai.providers.view', manage: 'ai.providers.manage',
                     fields: %w[name provider model api_key api_base], item_actions: %w[test] },
    'combos' => { gateway: :combos, view: 'ai.providers.view', manage: 'ai.providers.manage', fields: %w[name models] },
    'quotas' => { gateway: :summary, view: 'ai.usage.view', manage: nil, fields: [] },
    'usage' => { gateway: :usage, view: 'ai.usage.view', manage: nil, fields: [] },
    'requests' => { gateway: :requests, view: 'ai.usage.view', manage: nil, fields: [] },
    'runs' => { path: '/api/runs', paged: true, view: 'ai.runs.view', manage: nil, fields: [] },
    'environment' => { path: '/api/environment', view: 'ai.environment.view', manage: 'ai.environment.manage', fields: [],
                       actions: %w[start stop backup] },
    # Serviços em execução no ambiente da empresa (AMB-2). Só leitura aqui; ações e logs têm rotas próprias.
    'environment_services' => { path: '/api/environment/services', view: 'ai.environment.view', manage: nil, fields: [] },
    'inboxes' => { path: '/api/omnichannel/inboxes', view: 'ai.inbox_routing.view', manage: 'ai.inbox_routing.manage',
                   fields: [], update_suffix: '/ia', update_fields: %w[template_id autopilot handoff_team_id show_progress] },
    'integrations' => { path: '/api/integrations', view: 'ai.integrations.view', manage: 'ai.integrations.manage',
                        fields: %w[name] }
  }.freeze

  before_action :find_resource, except: [:service_action, :service_logs, :provider_catalog, :provider_validate, :provider_batch_test]
  before_action -> { require_permission(@rt_resource[:view]) }, only: [:index, :models]
  before_action -> { require_permission(@rt_resource[:manage].to_s) }, only: [:create, :update, :destroy, :action, :member_action]
  before_action -> { require_permission('ai.environment.manage') }, only: [:service_action, :service_logs]
  before_action :need_service_name, only: [:service_action, :service_logs]
  before_action -> { require_permission('ai.providers.view') }, only: [:provider_catalog]
  before_action -> { require_permission('ai.providers.manage') }, only: [:provider_validate, :provider_batch_test]
  before_action :need_id, only: [:update, :destroy, :member_action, :models]

  def index
    return render_gateway(gateway_get) if @rt_resource[:gateway]

    render_engine engine_get(index_path)
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

  # Iniciar/parar/reiniciar um serviço do ambiente (auditado no motor). Nome e ação em allowlist.
  def service_action
    return head :not_found unless SERVICE_ACTIONS.include?(params[:do])

    render_engine engine_post("/api/environment/services/#{params[:service]}/#{params[:do]}")
  end

  # Últimas 200 linhas do log do serviço (o motor redige segredos e audita a leitura).
  def service_logs
    render_engine engine_get("/api/environment/services/#{params[:service]}/logs")
  end

  # Metadados de UI versionados no próprio deploy (nome, categoria, ícone e
  # modos de autenticação). Não há chaves, URLs de gateway ou informações de
  # contas aqui; conexões continuam vindo exclusivamente pelo BFF tenant-scoped.
  def provider_catalog
    render json: JSON.parse(File.read(Rails.root.join('app/javascript/dashboard/routes/dashboard/ragent/provider_catalog.json')))
  rescue Errno::ENOENT, JSON::ParserError
    render json: { providers: [], generated_at: nil }, status: :service_unavailable
  end

  # A chave nunca volta ao navegador. O BFF apenas encaminha a tentativa de
  # validação ao Gateway já tenant-scoped e devolve o estado público.
  def provider_validate
    provider = params[:provider].to_s
    api_key = params[:api_key].to_s
    return render json: { code: 'invalid_provider', message: 'Provedor inválido' }, status: :unprocessable_entity unless PROVIDER_ID.match?(provider)
    return render json: { code: 'missing_api_key', message: 'Informe a chave de API para testar' }, status: :unprocessable_entity if api_key.blank?

    render_gateway Rt::GatewayClient.post(account: Current.account, path: '/api/providers/validate', payload: {
                                             provider: provider, apiKey: api_key
                                           })
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  # Porta fiel do teste em lote do 9Router. O BFF aceita somente o modo e o
  # identificador de provedor validados; Current.account continua sendo a
  # origem do tenant no GatewayClient.
  def provider_batch_test
    mode = params[:mode].to_s
    provider_id = params[:provider_id].to_s
    return render json: { code: 'invalid_batch_test', message: 'Teste em lote inválido' }, status: :unprocessable_entity unless PROVIDER_BATCH_MODES.include?(mode)
    return render json: { code: 'invalid_batch_test', message: 'Provedor inválido' }, status: :unprocessable_entity if mode == 'provider' && !PROVIDER_ID.match?(provider_id)
    return render json: { code: 'invalid_batch_test', message: 'Provedor não permitido para este modo' }, status: :unprocessable_entity if mode != 'provider' && provider_id.present?

    payload = { mode: mode }
    payload[:providerId] = provider_id if mode == 'provider'
    render_gateway Rt::GatewayClient.post(account: Current.account, path: '/api/providers/test-batch', payload: payload)
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  private

  # Listas paginadas: só page/per_page numéricos seguem ao motor (nada livre do navegador).
  def index_path
    return @rt_resource[:path] unless @rt_resource[:paged]

    page = params[:page].to_i.clamp(1, 10_000)
    per_page = params[:per_page].to_i.clamp(1, 100)
    per_page = 25 if params[:per_page].blank?
    "#{@rt_resource[:path]}?page=#{page}&per_page=#{per_page}"
  end

  def need_service_name
    head :not_found unless SERVICE_NAME.match?(params[:service].to_s)
  end

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
    body = params.permit(:name, :model, :api_key, :is_active, :priority, models: []).to_h
    if @rt_resource[:gateway] == :providers
      payload = { name: body['name'], apiKey: body['api_key'], defaultModel: body['model'], isActive: body['is_active'], priority: body['priority'] }.compact
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
  # O gateway responde em inglês e fala em "tenant": o cliente recebe o equivalente em português, sem o termo interno.
  GATEWAY_MESSAGES = [
    [/provider of "([^"]+)" is not configured/i, ->(m) { "O provedor do modelo \"#{m[1]}\" não está configurado nesta empresa." }],
    [/combo .*not found|unknown combo/i, ->(_) { 'Combo não encontrado nesta empresa.' }],
    [/already exists|duplicate/i, ->(_) { 'Já existe um item com esse nome.' }]
  ].freeze
  GATEWAY_DEFAULT_MESSAGE = 'O gateway recusou a operação. Revise os dados e tente novamente.'.freeze

  def gateway_message(error)
    text = error.body.is_a?(Hash) ? error.body['error'] : nil
    return nil unless text.is_a?(String)

    GATEWAY_MESSAGES.each do |pattern, builder|
      match = pattern.match(text)
      return builder.call(match) if match
    end
    GATEWAY_DEFAULT_MESSAGE
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
