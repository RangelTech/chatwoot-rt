require 'stringio'

# H-6: proxy genérico para o agente de IA operar o Chatwoot COMO o usuário do chat.
# Reexecuta a requisição na API normal (Rack interno) com o access token do usuário,
# então todas as policies do Chatwoot continuam valendo. Auth: X-Luar-Context (aud `luar`).
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class RtLuar::ProxyController < ActionController::API
  BACKSLASH = 92.chr
  RATE_LIMIT = 120
  RATE_PERIOD = 60
  PASS_HEADERS = %w[CONTENT_TYPE HTTP_ACCEPT HTTP_ACCEPT_LANGUAGE].freeze
  # Segmentos de gestão (usuários, perfis, contas) e credenciais: sempre bloqueados.
  BLOCKED_SEGMENTS = %w[agents account_users custom_roles].freeze
  CREDENTIAL_SEGMENT = /password|token|api_key|secret/
  # Saídas para o cliente final / terceiros.
  OUTBOUND_MEMBER_ACTIONS = %w[transcript].freeze

  before_action :authenticate_context
  before_action :ensure_same_account
  before_action :load_account_user
  before_action :normalize_path
  before_action :enforce_blocklist
  before_action :enforce_rate_limit

  def handle
    status, headers, body = dispatch_internal
    chunks = []
    body.each { |chunk| chunks << chunk } # rubocop:disable Style/MapIntoArray
    body.close if body.respond_to?(:close)
    audit(status)
    ctype = headers['Content-Type'] || headers['content-type'] || 'application/json'
    render body: chunks.join, status: status, content_type: ctype
  end

  private

  def deny(status, code, message)
    audit(status, force: true) if @claims
    render json: { code: code, message: message }, status: status
  end

  def authenticate_context
    @claims = Rt::LuarContext.verify(request.headers['X-Luar-Context'])
  rescue Rt::LuarContext::Invalid, KeyError
    render json: { code: 'luar_unauthorized', message: 'Contexto inválido ou expirado' }, status: :unauthorized
  end

  def ensure_same_account
    return if params[:account_id].to_s == @claims['account_id'].to_s

    deny(:forbidden, 'luar_blocked', 'Conta do caminho difere da conta do contexto')
  end

  def load_account_user
    @account_user = AccountUser.find_by(account_id: @claims['account_id'], user_id: @claims['user_id'])
    return if @account_user&.user

    deny(:forbidden, 'luar_blocked', 'Usuário não é membro da conta')
  end

  def normalize_path
    raw = params[:path].to_s
    decoded = CGI.unescape(raw)
    invalid = [raw, decoded].any? { |p| p.include?('..') || p.include?(BACKSLASH) || p.include?("\0") || p.include?('//') }
    return deny(:forbidden, 'luar_blocked', 'Caminho inválido') if invalid

    @segments = decoded.split('/').compact_blank
  end

  def enforce_blocklist
    reason = block_reason
    deny(:forbidden, 'luar_blocked', reason) if reason
  end

  def block_reason
    verb = request.request_method
    first = @segments.first.to_s
    return 'Gestão de contas bloqueada' if @segments.empty? && verb != 'GET'
    return 'Gestão de usuários e perfis bloqueada' if BLOCKED_SEGMENTS.include?(first) ||
                                                      (first == 'rt_ai' && @segments[1] == 'members')
    return 'Credenciais e tokens bloqueados' if @segments.any? { |s| s.match?(CREDENTIAL_SEGMENT) }
    return 'O proxy não pode chamar a si mesmo' if first.start_with?('rt_luar')
    return 'Exclusão de inbox bloqueada' if verb == 'DELETE' && first == 'inboxes' && @segments.size == 2

    outbound_block_reason
  end

  def outbound_block_reason
    return unless request.post? && @segments.first == 'conversations' && !outbound_enabled?
    return unless outbound_request?

    'Mensagem para o cliente exige outbound_enabled na conta'
  end

  def outbound_request?
    case @segments
    in ['conversations'] then body_params['message'].present?
    in ['conversations', _, 'messages'] then !private_message?
    in ['conversations', _, 'messages', _, 'retry'] then true
    in ['conversations', _, action] then OUTBOUND_MEMBER_ACTIONS.include?(action)
    else false
    end
  end

  def private_message?
    ActiveModel::Type::Boolean.new.cast(body_params['private']) == true
  end

  def body_params
    @body_params ||= begin
      parsed = request.media_type.to_s.include?('json') ? JSON.parse(request.raw_post.presence || '{}') : request.request_parameters
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end

  def outbound_enabled?
    Rt::AiAccount.find_by(account_id: @claims['account_id'])&.effective_flags&.dig('outbound_enabled') == true
  end

  def enforce_rate_limit
    count = Rack::Attack.cache.count("rt_luar:#{@claims['user_id']}", RATE_PERIOD)
    return if count <= RATE_LIMIT

    deny(:too_many_requests, 'luar_rate_limited', 'Limite de requisições excedido')
  end

  def dispatch_internal
    path = "/api/v1/accounts/#{@claims['account_id']}/#{@segments.map { |s| CGI.escape(s) }.join('/')}".chomp('/')
    env = Rack::MockRequest.env_for(
      request.query_string.present? ? "#{path}?#{request.query_string}" : path,
      :method => request.request_method, :input => StringIO.new(request.raw_post.to_s),
      'REMOTE_ADDR' => request.remote_ip.to_s, 'HTTP_HOST' => request.host_with_port, 'rack.url_scheme' => request.scheme
    )
    PASS_HEADERS.each { |h| env[h] = request.env[h] if request.env[h] }
    env['HTTP_API_ACCESS_TOKEN'] = @account_user.user.access_token.token
    Rails.application.call(env)
  end

  def audit(status, force: false)
    return if @audited && !force

    @audited = true
    Rt::LuarAudit.create!(account_id: @claims['account_id'], user_id: @claims['user_id'], run_id: @claims['run_id'].to_s.first(100),
                          http_method: request.request_method,
                          path: "/api/v1/accounts/#{@claims['account_id']}/#{@segments&.join('/') || ''}".first(500),
                          status: Rack::Utils.status_code(status), created_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("rt_luar audit failed: #{e.message}")
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
