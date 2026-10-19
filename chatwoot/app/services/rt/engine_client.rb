require 'net/http'

# Cliente do motor de IA (rede interna). Autentica com o contexto assinado
# (mesmo formato do `app/ui_context.py` do motor): base64url(claims).base64url(hmac).
class Rt::EngineClient
  class Error < StandardError
    # `status` e `body` (já em JSON, quando der) permitem repassar erro de validação ao usuário.
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  TTL = 30

  def self.sign(claims)
    body = Base64.urlsafe_encode64(claims.to_json, padding: false)
    sig = Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256', key, body), padding: false)
    "#{body}.#{sig}"
  end

  def self.key
    Digest::SHA256.digest("ui-context:#{ENV.fetch('RT_UI_CONTEXT_SECRET')}")
  end

  def self.install_context(scopes: ['lifecycle'])
    now = Time.now.to_i
    { aud: 'install', scopes: scopes, nonce: SecureRandom.hex(16), iat: now, exp: now + TTL }
  end

  def self.ui_context(account:, user:, account_user:, scopes: nil)
    ai = Rt::AiAccount.find_by!(account_id: account.id)
    now = Time.now.to_i
    { aud: 'ui', account_id: account.id, chatwoot_user_id: user.id, engine_tenant_id: ai.engine_tenant_id,
      email: user.email, name: user.name, scopes: scopes || account_user.permissions.grep(/\Aai\./),
      flags: ai.effective_flags, nonce: SecureRandom.hex(16), iat: now, exp: now + TTL }
  end

  def self.post(path, payload, claims: install_context)
    request(Net::HTTP::Post, path, payload, claims)
  end

  def self.put(path, payload, claims:)
    request(Net::HTTP::Put, path, payload, claims)
  end

  def self.delete(path, claims:)
    request(Net::HTTP::Delete, path, nil, claims)
  end

  def self.get(path, claims:)
    request(Net::HTTP::Get, path, nil, claims)
  end

  def self.request(verb, path, payload, claims)
    uri = URI.join(ENV.fetch('RT_ENGINE_URL'), path)
    req = verb.new(uri, 'Content-Type' => 'application/json', 'X-UI-Context' => sign(claims))
    req.body = payload.to_json if payload
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 30) do |http|
      http.request(req)
    end
    unless response.is_a?(Net::HTTPSuccess)
      raise Error.new("#{response.code} #{response.body.to_s.truncate(300)}",
                      status: response.code.to_i, body: parse_error_body(response.body))
    end

    JSON.parse(response.body)
  end

  MAX_DOWNLOAD_BYTES = 50 * 1024 * 1024
  MAX_REDIRECTS = 3

  # Baixa um arquivo do motor (que pode responder com redirecionamento para URL assinada do storage).
  # O contexto assinado só vai ao motor; o destino do redirecionamento recebe a requisição sem ele.
  # Devolve { body:, content_type: }.
  def self.download(path, claims:)
    uri = URI.join(ENV.fetch('RT_ENGINE_URL'), path)
    headers = { 'X-UI-Context' => sign(claims) }
    (MAX_REDIRECTS + 1).times do
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 60) do |http|
        http.request(Net::HTTP::Get.new(uri, headers))
      end
      if response.is_a?(Net::HTTPRedirection) && response['location'].present?
        uri = URI.join(uri.to_s, response['location'])
        headers = {}
        next
      end
      raise Error.new("#{response.code} download", status: response.code.to_i, body: parse_error_body(response.body)) unless response.is_a?(Net::HTTPSuccess)
      raise Error.new('413 download', status: 413) if response.body.to_s.bytesize > MAX_DOWNLOAD_BYTES

      return { body: response.body.to_s, content_type: response['content-type'].to_s.split(';').first.presence || 'application/octet-stream' }
    end
    raise Error, 'redirecionamentos demais'
  end

  def self.parse_error_body(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    nil
  end
end
