# Fase F: o agente fica vinculado a FILA, nao a caixa. Para a bridge poder responder numa fila de IA ela precisa
# (1) de uma chave de integracao do tenant e (2) de um Agent Bot ligado a caixa. Ambos nascem aqui, sem tela extra.
# Falha nunca derruba o salvamento da fila: devolve :degraded e o salvamento pode ser repetido.
class Rt::Routing::BridgeSync
  BOT_NAME = 'LUAR filas'.freeze

  # Chave padrao do tenant na bridge (linha sem caixa). Idempotente: so cria se a bridge ainda nao tem chave.
  def self.ensure_key(account:, claims:)
    ai = Rt::AiAccount.find_by(account_id: account.id)
    return :skipped if ai&.engine_tenant_id.blank? || ENV['BRIDGE_URL'].blank? || ENV['BRIDGE_ADMIN_TOKEN'].blank?
    return :ok if bridge_has_key?(ai.engine_tenant_id)

    created = Rt::EngineClient.post('/api/integrations', { name: "luar-filas-#{SecureRandom.hex(3)}" }, claims: claims)
    key = created['api_key']
    return :degraded if key.blank?

    res = bridge_post('/admin/ai-config', { tenant_id: ai.engine_tenant_id, chatwoot_inbox_id: nil, integration_key: key,
                                            autopilot: true })
    res.success? ? :ok : :degraded
  rescue StandardError => e
    Rails.logger.warn("rt bridge key sync: #{e.class}")
    :degraded
  end

  # Liga o Agent Bot da conta (criado uma vez) a caixa, para o Chatwoot avisar a bridge de cada mensagem.
  def self.ensure_inbox_bot(inbox)
    url = ENV['BRIDGE_PUBLIC_URL'].presence || ENV['BRIDGE_URL'].presence
    return :skipped if url.blank?

    account = inbox.account
    bot = account.agent_bots.find_by(name: BOT_NAME) ||
          account.agent_bots.create!(name: BOT_NAME, outgoing_url: "#{url.chomp('/')}/agent-bot", bot_type: :webhook)
    AgentBotInbox.find_or_create_by!(inbox: inbox, account: account) { |abi| abi.agent_bot = bot }
    :ok
  rescue StandardError => e
    Rails.logger.warn("rt inbox bot sync: #{e.class}")
    :degraded
  end

  def self.bridge_has_key?(tenant_id)
    res = HTTParty.get("#{ENV.fetch('BRIDGE_URL')}/admin/ai-config/status", query: { tenant_id: tenant_id },
                                                                          headers: headers, timeout: 15)
    res.success? && res.parsed_response['has_integration_key'] == true
  end

  def self.bridge_post(path, body)
    HTTParty.post("#{ENV.fetch('BRIDGE_URL')}#{path}", headers: headers.merge('Content-Type' => 'application/json'),
                                                     body: body.to_json, timeout: 60)
  end

  def self.headers
    { 'Authorization' => "Bearer #{ENV.fetch('BRIDGE_ADMIN_TOKEN')}" }
  end
  private_class_method :bridge_has_key?, :bridge_post, :headers
end
