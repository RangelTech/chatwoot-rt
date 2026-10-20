# BFF de cadastros de IA (spec 10, U-4): provedores, uso, execuções, ambiente e integrações.
# Credenciais (segredos, bancos, SSH, GCP, e-mail, pagamento, OAuth) vivem em CredentialsController.
# Allowlist fixa por domínio: nada de URL ou método vindos do navegador. Segredos só entram (write-only).
class Api::V1::Accounts::RtAi::ResourcesController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i

  RESOURCES = {
    'providers' => { path: '/api/ai-services', view: 'ai.providers.view', manage: 'ai.providers.manage',
                     fields: %w[name provider model api_key api_base] },
    'usage' => { path: '/api/usage', view: 'ai.usage.view', manage: nil, fields: [] },
    'runs' => { path: '/api/hermes/sessions', view: 'ai.runs.view', manage: nil, fields: [] },
    'environment' => { path: '/api/environment', view: 'ai.environment.view', manage: 'ai.environment.manage', fields: [],
                       actions: %w[start stop backup] },
    'inboxes' => { path: '/api/omnichannel/inboxes', view: 'ai.inbox_routing.view', manage: 'ai.inbox_routing.manage',
                   fields: [], update_suffix: '/ia', update_fields: %w[template_id autopilot handoff_team_id] },
    'integrations' => { path: '/api/integrations', view: 'ai.integrations.view', manage: 'ai.integrations.manage',
                        fields: %w[name] }
  }.freeze

  before_action :find_resource
  before_action -> { require_permission(@rt_resource[:view]) }, only: [:index]
  before_action -> { require_permission(@rt_resource[:manage].to_s) }, only: [:create, :update, :destroy, :action]
  before_action :need_id, only: [:update, :destroy]

  def index
    render_engine engine_get(@rt_resource[:path])
  end

  def create
    body = params.permit(*@rt_resource[:fields]).to_h
    body['config'] = params[:config].to_unsafe_h if params[:config].respond_to?(:to_unsafe_h)
    render_engine engine_post(@rt_resource[:path], body)
  end

  def update
    return head :not_found if @rt_resource[:update_fields].blank?

    path = "#{@rt_resource[:path]}/#{params[:id]}#{@rt_resource[:update_suffix]}"
    render_engine engine_put(path, params.permit(*@rt_resource[:update_fields]).to_h)
  end

  def destroy
    render_engine engine_delete("#{@rt_resource[:path]}/#{params[:id]}")
  end

  def action
    return head :not_found unless Array(@rt_resource[:actions]).include?(params[:name])

    render_engine engine_post("#{@rt_resource[:path]}/#{params[:name]}")
  end

  private

  def find_resource
    @rt_resource = RESOURCES[params[:key]]
    head :not_found if @rt_resource.nil?
  end

  def render_engine(data)
    render json: data unless performed?
  end

  def need_id
    head :not_found unless UUID.match?(params[:id].to_s) || params[:id].to_s.match?(/\A\d{1,10}\z/)
  end
end
