# Consulta ao motor: o agente (template) esta publicado e e do tenant da conta?
# Devolve true | false | nil (desconhecido: motor indisponivel ou contrato ainda nao exposto).
# nil NAO bloqueia o cadastro; o resolver trata agente nao confirmado como "nao publicado" em tempo de decisao (F-2).
class Rt::Routing::TemplateLookup
  def self.published?(account:, template_id:)
    return nil if ENV['RT_ENGINE_URL'].blank?

    ai = Rt::AiAccount.find_by(account_id: account.id)
    return nil if ai&.engine_tenant_id.blank?

    data = Rt::EngineClient.get("/api/internal/templates/#{template_id}/status", claims: claims(account, ai))
    return false unless data['tenant_id'].to_s == ai.engine_tenant_id.to_s

    data['published'] == true
  rescue Rt::EngineClient::Error => e
    e.status == 404 ? false : nil
  end

  def self.claims(account, ai)
    now = Time.now.to_i
    { aud: 'install', scopes: ['routing'], account_id: account.id, engine_tenant_id: ai.engine_tenant_id,
      nonce: SecureRandom.hex(16), iat: now, exp: now + Rt::EngineClient::TTL }
  end
end
