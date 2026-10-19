require 'net/http'

# Cliente do motor de IA (rede interna). Autentica com o contexto assinado
# (mesmo formato do `app/ui_context.py` do motor): base64url(claims).base64url(hmac).
class Rt::EngineClient
  class Error < StandardError; end

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
    raise Error, "#{response.code} #{response.body.to_s.truncate(300)}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
