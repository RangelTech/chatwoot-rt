# Espelho de Evolution::ProvisioningService, sentido contrário. Achado real
# 24/08/2026 (dono reportou ao testar): apagar a inbox no Chatwoot nunca
# desligava o container/Postgres/Redis reais na VPS nem a linha em
# `evolution_connections` da ponte -- "deletar e criar de novo" reconectava
# na MESMA sessão WhatsApp já logada (pulava direto pro estado conectado,
# sem QR novo), parecendo bug de fluxo quando na verdade era infra órfã
# sobrevivendo por baixo. Ver produto-09 seção 1z (mesma família de
# problema do lado do bind mount de dado, agora fechada dos dois lados).
class Evolution::DeprovisioningService
  class DeprovisioningError < StandardError; end

  def initialize(channel:)
    @channel = channel
  end

  def call
    response = HTTParty.post(
      "#{bridge_url}/admin/evolution/deprovision",
      headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{bridge_admin_token}" },
      body: { chatwoot_account_id: channel.inbox.account_id, instance_name: channel.instance_name }.to_json,
      timeout: 60
    )
    raise DeprovisioningError, "ponte indisponível: #{response.code}" unless response.success?
  rescue StandardError => e
    raise e if e.is_a?(DeprovisioningError)

    raise DeprovisioningError, "falha ao desprovisionar instância WhatsApp: #{e.message}"
  end

  private

  attr_reader :channel

  def bridge_url
    ENV.fetch('BRIDGE_URL') { raise DeprovisioningError, 'BRIDGE_URL não configurada' }
  end

  def bridge_admin_token
    ENV.fetch('BRIDGE_ADMIN_TOKEN') { raise DeprovisioningError, 'BRIDGE_ADMIN_TOKEN não configurado' }
  end
end
