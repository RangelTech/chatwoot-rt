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

  # Achado real 25/08/2026, testado ao vivo via SSH: chamar isto a partir de
  # um `before_destroy` em Channel::EvolutionApi quebrava sempre com
  # "undefined method 'account_id' for nil" -- `channel.inbox` já vem nil
  # nesse ponto (a cascata de destroy em `has_one :inbox, dependent:
  # :destroy_async` limpa a associação reversa antes do callback do canal
  # rodar). Por isso o serviço recebe account_id/instance_name explícitos
  # em vez de navegar `channel.inbox` -- chamado do `before_destroy` do
  # Inbox (que ainda tem `account_id` como coluna própria e `channel`
  # intacto), não do Channel.
  def initialize(account_id:, instance_name:)
    @account_id = account_id
    @instance_name = instance_name
  end

  def call
    response = HTTParty.post(
      "#{bridge_url}/admin/evolution/deprovision",
      headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{bridge_admin_token}" },
      body: { chatwoot_account_id: account_id, instance_name: instance_name }.to_json,
      timeout: 60
    )
    raise DeprovisioningError, "ponte indisponível: #{response.code}" unless response.success?
  rescue StandardError => e
    raise e if e.is_a?(DeprovisioningError)

    raise DeprovisioningError, "falha ao desprovisionar instância WhatsApp: #{e.message}"
  end

  private

  attr_reader :account_id, :instance_name

  def bridge_url
    ENV.fetch('BRIDGE_URL') { raise DeprovisioningError, 'BRIDGE_URL não configurada' }
  end

  def bridge_admin_token
    ENV.fetch('BRIDGE_ADMIN_TOKEN') { raise DeprovisioningError, 'BRIDGE_ADMIN_TOKEN não configurado' }
  end
end
