require 'net/http'

# Cliente HTTP síncrono do gateway de canais (docs/canais/CONTRATO_GATEWAY.md).
# Rede interna; Authorization: Bearer CHANNELS_GATEWAY_TOKEN. Senha e código de
# verificação passam SÓ por aqui, na requisição em andamento: nunca por job/Sidekiq.
# Nenhuma mensagem de erro carrega corpo de requisição (evita vazar segredo em log).
class Channels::GatewayClient
  class Error < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      @status = status
      @code = code.to_s.presence || 'provider_unavailable'
      super("gateway #{status || 'unreachable'}: #{@code}")
    end
  end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 25

  def self.configured?
    ENV['CHANNELS_GATEWAY_URL'].present? && ENV['CHANNELS_GATEWAY_TOKEN'].present?
  end

  def initialize(account_id: nil)
    @account_id = account_id
  end

  def catalog = request(:get, '/catalog')

  def list(account_id:) = request(:get, '/connections', query: { account_id: account_id })

  def create_connection(account_id:, provider:, actor_id:, consent:, login_flow: nil)
    body = { account_id: account_id, provider: provider, actor_id: actor_id.to_s, consent: consent }
    body[:login_flow] = login_flow if login_flow.present?
    request(:post, '/connections', body: body)
  end

  def show(id) = request(:get, "/connections/#{path_id(id)}")

  def step(id, step_id:, kind:, data:)
    request(:post, "/connections/#{path_id(id)}/step", body: { step_id: step_id, kind: kind, data: data })
  end

  def cancel(id) = request(:post, "/connections/#{path_id(id)}/cancel")
  def disconnect(id) = request(:post, "/connections/#{path_id(id)}/disconnect")
  def revoke(id) = request(:post, "/connections/#{path_id(id)}/revoke")
  def reauth(id) = request(:post, "/connections/#{path_id(id)}/reauth")

  def delivery(id, webhook_url:, webhook_secret:, inbox_ref:)
    request(:put, "/connections/#{path_id(id)}/delivery",
            body: { webhook_url: webhook_url, webhook_secret: webhook_secret, inbox_ref: inbox_ref })
  end

  def sync(id, since_days: 60)
    request(:post, "/connections/#{path_id(id)}/sync", body: { since_days: since_days })
  end

  def send_message(id, idempotency_key:, conversation_ref:, text:, attachments: nil, reply_to: nil)
    body = { idempotency_key: idempotency_key.to_s, conversation_ref: conversation_ref, text: text }
    body[:attachments] = attachments if attachments.present?
    body[:reply_to] = reply_to if reply_to.present?
    request(:post, "/connections/#{path_id(id)}/send", body: body)
  end

  # Download de anexo por URL assinada do gateway. Só aceita URL sob CHANNELS_GATEWAY_URL
  # (evita SSRF por payload de webhook); devolve { body:, content_type: }.
  def download(url)
    base = base_uri
    uri = URI.parse(url.to_s)
    raise Error.new(nil, 'unsupported_step') unless uri.host == base.host && uri.port == base.port && uri.scheme == base.scheme

    response = http_for(uri).request(Net::HTTP::Get.new(uri.request_uri, auth_headers))
    raise Error.new(response.code.to_i, 'provider_unavailable') unless response.is_a?(Net::HTTPSuccess)

    { body: response.body, content_type: response['Content-Type'] }
  rescue URI::InvalidURIError, SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout
    raise Error.new(nil, 'provider_unavailable')
  end

  private

  def path_id(id)
    raise Error.new(nil, 'unsupported_step') unless id.to_s.match?(/\A[0-9a-fA-F-]{8,64}\z/)

    id
  end

  def base_uri
    URI.parse(ENV.fetch('CHANNELS_GATEWAY_URL', '').chomp('/'))
  end

  def auth_headers
    headers = { 'Authorization' => "Bearer #{ENV.fetch('CHANNELS_GATEWAY_TOKEN', '')}", 'Accept' => 'application/json' }
    headers['X-Luar-Account-Id'] = @account_id.to_s if @account_id
    headers
  end

  def http_for(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http
  end

  def request(verb, path, body: nil, query: nil)
    raise Error.new(nil, 'provider_unavailable') unless self.class.configured?

    uri = URI.parse("#{base_uri}/internal/channels#{path}")
    uri.query = query.to_query if query
    response = http_for(uri).request(build_request(verb, uri, body))
    parse(response)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
    raise Error.new(nil, 'provider_unavailable')
  end

  def build_request(verb, uri, body)
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(verb)
    req = klass.new(uri.request_uri, auth_headers)
    return req if body.nil? && verb == :get

    req['Content-Type'] = 'application/json'
    req.body = (body || {}).to_json
    req
  end

  def parse(response)
    status = response.code.to_i
    parsed = response.body.present? ? JSON.parse(response.body) : {}
    return parsed.with_indifferent_access if status.between?(200, 299) && parsed.is_a?(Hash)

    raise Error.new(status, error_code_from(parsed, status))
  rescue JSON::ParserError
    raise Error.new(status, 'provider_unavailable')
  end

  def error_code_from(parsed, status)
    code = parsed.is_a?(Hash) ? (parsed['error_code'] || parsed['code'] || (parsed['detail'].is_a?(Hash) ? parsed['detail']['error_code'] : (parsed['detail'].is_a?(String) ? parsed['detail'] : nil))) : nil
    code = code.to_s if code
    return code if code&.match?(/\A[a-z_]{3,40}\z/)

    status == 429 ? 'too_many_attempts' : 'provider_unavailable'
  end
end
