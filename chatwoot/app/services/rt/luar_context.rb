# Contexto assinado do proxy Luar (H-6): mesmo formato do X-UI-Context
# (base64url(claims).base64url(HMAC-SHA256)), aud `luar`, reutilizável durante a run (sem nonce).
class Rt::LuarContext
  AUD = 'luar'.freeze
  MAX_TTL = 15.minutes.to_i

  class Invalid < StandardError; end

  def self.mint(account_id:, user_id:, run_id:, ttl: MAX_TTL)
    now = Time.now.to_i
    Rt::EngineClient.sign(aud: AUD, account_id: account_id.to_i, user_id: user_id.to_i, run_id: run_id.to_s,
                          iat: now, exp: now + [ttl.to_i, MAX_TTL].min)
  end

  # Devolve os claims (Hash com chaves string) ou levanta Invalid.
  def self.verify(token)
    body, sig = token.to_s.split('.', 2)
    raise Invalid, 'malformed' if body.blank? || sig.blank?

    expected = Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256', Rt::EngineClient.key, body), padding: false)
    raise Invalid, 'signature' unless ActiveSupport::SecurityUtils.secure_compare(expected, sig)

    claims = JSON.parse(Base64.urlsafe_decode64(body))
    validate!(claims)
    claims
  rescue JSON::ParserError, ArgumentError
    raise Invalid, 'malformed'
  end

  def self.validate!(claims) # rubocop:disable Metrics/CyclomaticComplexity
    raise Invalid, 'aud' unless claims.is_a?(Hash) && claims['aud'] == AUD
    raise Invalid, 'claims' unless claims['account_id'].to_i.positive? && claims['user_id'].to_i.positive? && claims['run_id'].present?

    exp = claims['exp'].to_i
    now = Time.now.to_i
    raise Invalid, 'expired' if exp <= now
    raise Invalid, 'ttl' if exp - now > MAX_TTL
  end
end
