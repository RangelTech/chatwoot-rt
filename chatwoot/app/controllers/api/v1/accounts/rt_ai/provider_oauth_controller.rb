# Cadastro de provedor por OAuth (spec 10, G-3). O tenant vem sempre da Account da sessão
# (Rt::GatewayClient). PKCE/estado e device code ficam no servidor, presos à Account:
# o browser só recebe a URL de autorização, o código do usuário e um identificador opaco.
class Api::V1::Accounts::RtAi::ProviderOauthController < Api::V1::Accounts::RtAi::BaseController
  AUTH_CODE = %w[codex claude gemini-cli].freeze
  DEVICE = %w[github].freeze
  IMPORT_TOKEN = %w[codex].freeze
  PENDING_TTL = 10.minutes
  DEFAULT_REDIRECT = 'http://localhost:8080/callback'.freeze
  HANDLE = /\A[0-9a-f]{32}\z/
  UUID = /\A[0-9a-f-]{36}\z/i

  before_action :find_provider, except: [:quota]
  before_action -> { require_permission('ai.providers.manage') }, except: [:quota]
  before_action -> { require_permission('ai.providers.view') }, only: [:quota]

  # GET .../providers_oauth/:provider/start
  def start
    return simulated_start if simulator?

    return start_device if DEVICE.include?(@provider)
    return head :not_found unless AUTH_CODE.include?(@provider)

    redirect = redirect_uri
    data = Rt::GatewayClient.get(account: Current.account,
                                 path: "/api/oauth/#{@provider}/authorize?redirect_uri=#{CGI.escape(redirect)}")
    handle = remember('codeVerifier' => data['codeVerifier'], 'redirectUri' => redirect, 'state' => data['state'])
    render json: { auth_url: data['authUrl'], state: handle, flow: 'authorization_code' }
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  # POST .../providers_oauth/:provider/finish  { state, callback_url }  (cole a URL de retorno)
  def finish
    return simulated_finish if simulator?
    return head :not_found unless AUTH_CODE.include?(@provider)

    pending = recall(params[:state])
    return render_expired unless pending

    code, returned_state = extract_code(params[:callback_url].to_s)
    return render_invalid('invalid_callback', 'URL de retorno inválida') if code.blank?
    return render_invalid('state_mismatch', 'Estado de autorização não confere') if pending['state'].present? && returned_state != pending['state']

    data = Rt::GatewayClient.post(account: Current.account, path: "/api/oauth/#{@provider}/exchange", payload: {
      code: code, redirectUri: pending['redirectUri'], codeVerifier: pending['codeVerifier'], state: pending['state']
    }.compact)
    forget(params[:state])
    render json: data['connection'] || data
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  # POST .../providers_oauth/:provider/poll  { state }  (device code)
  def poll
    return simulated_finish if simulator?
    return head :not_found unless DEVICE.include?(@provider)

    pending = recall(params[:state])
    return render_expired unless pending

    data = Rt::GatewayClient.post(account: Current.account, path: "/api/oauth/#{@provider}/poll", payload: {
      deviceCode: pending['deviceCode'], codeVerifier: pending['codeVerifier'], extraData: pending['extraData']
    }.compact)
    forget(params[:state]) if data['success']
    render json: { success: !!data['success'], pending: !!data['pending'], connection: data['connection'] }.compact
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  # POST .../providers_oauth/:provider/import  { access_token, name }
  def import
    return head :not_found unless IMPORT_TOKEN.include?(@provider)
    return render_invalid('invalid_token', 'Token obrigatório') if params[:access_token].blank?

    data = Rt::GatewayClient.post(account: Current.account, path: "/api/oauth/#{@provider}/import-token",
                                  payload: { accessToken: params[:access_token].to_s, name: params[:name].presence }.compact)
    render json: data['connection'] || data
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  # GET .../providers/:id/quota  (cota/limite do provedor; só do tenant da sessão)
  def quota
    return head :not_found unless UUID.match?(params[:id].to_s)

    render json: Rt::GatewayClient.get(account: Current.account, path: "/api/usage/#{params[:id]}")
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  private

  def find_provider
    @provider = params[:provider].to_s
    head :not_found unless (AUTH_CODE + DEVICE + IMPORT_TOKEN).include?(@provider)
  end

  def start_device
    data = Rt::GatewayClient.get(account: Current.account, path: "/api/oauth/#{@provider}/device-code")
    handle = remember(data.slice('deviceCode', 'codeVerifier', 'extraData'))
    render json: data.slice('userCode', 'verificationUri', 'verificationUriComplete', 'expiresIn', 'interval')
                     .merge('state' => handle, 'flow' => 'device_code')
  end

  def redirect_uri
    ENV['GATEWAY_OAUTH_REDIRECT_URI'].presence || DEFAULT_REDIRECT
  end

  def extract_code(raw)
    query = Rack::Utils.parse_query(URI.parse(raw.strip).query.to_s)
    [query['code'], query['state']]
  rescue URI::InvalidURIError
    [nil, nil]
  end

  def cache_key(handle)
    "rt_ai:oauth:#{Current.account.id}:#{handle}"
  end

  def remember(payload)
    handle = SecureRandom.hex(16)
    Rails.cache.write(cache_key(handle), payload.to_h, expires_in: PENDING_TTL)
    handle
  end

  def recall(handle)
    return nil unless HANDLE.match?(handle.to_s)

    Rails.cache.read(cache_key(handle))
  end

  def forget(handle)
    Rails.cache.delete(cache_key(handle))
  end

  def render_invalid(code, message)
    render json: { code: code, message: message }, status: :unprocessable_entity
  end

  def render_expired
    render_invalid('oauth_expired', 'Autorização expirada. Comece de novo.')
  end

  # Simulador (QA/ensaio, sem conta real). Flag `oauth_simulator` da Account; cria uma conexão
  # `codex` do próprio tenant com token fictício, pelo mesmo caminho de importação.
  def simulator?
    Rt::AiAccount.find_by(account_id: Current.account.id)&.effective_flags&.dig('oauth_simulator') == true
  end

  def simulated_start
    render json: { auth_url: 'simulator://authorize', state: remember('simulated' => true), flow: 'simulator' }
  end

  def simulated_finish
    return render_expired unless recall(params[:state])

    forget(params[:state])
    claims = Base64.urlsafe_encode64({ email: "simulador+#{SecureRandom.hex(3)}@example.invalid" }.to_json, padding: false)
    fake = [Base64.urlsafe_encode64('{"alg":"none"}', padding: false), claims, 'sim'].join('.')
    data = Rt::GatewayClient.post(account: Current.account, path: '/api/oauth/codex/import-token',
                                  payload: { accessToken: fake, name: "Simulador #{@provider}" })
    render json: (data['connection'] || data).merge('simulated' => true)
  rescue Rt::GatewayClient::Error => e
    gateway_failed(e)
  end

  # Erro de validação do gateway (ex.: provedor que o tenant não tem) é texto de negócio, sem segredo.
  def gateway_message(error)
    text = error.body.is_a?(Hash) ? error.body['error'] : nil
    text.is_a?(String) ? text.first(300) : nil
  end

  def gateway_failed(error)
    Rails.logger.warn("rt_ai oauth gateway error: #{error.message}")
    status = PASSTHROUGH_STATUSES.include?(error.status) ? error.status : :bad_gateway
    message = gateway_message(error) if status != :bad_gateway
    render json: { code: 'gateway_error', message: message || 'Gateway de IA indisponível no momento' }, status: status
  end
end
