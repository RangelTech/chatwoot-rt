# Produto-05 seção 4 -- QR automático. Chama a ponte (control-plane
# server-a-servidor, `chatwoot-bridge` no Cloud Run) para provisionar a
# instância Evolution deste tenant, sem que o administrador jamais precise
# saber ou digitar instance_name/api_url/api_key.
#
# `Current.account.id` é a única identidade que este serviço envia -- é o
# que a sessão autenticada do Rails já garante pertencer ao usuário que
# clicou o botão. A ponte resolve essa conta para o tenant certo do lado
# dela (`tenant_link_by_account`); não existe parâmetro aqui que um tenant
# mal-intencionado possa manipular para provisionar em nome de outro.
class Evolution::ProvisioningService
  class ProvisioningError < StandardError; end

  def initialize(account:, indice: 1)
    @account = account
    @indice = indice
  end

  # Devolve o Inbox pronto para uso (criado agora ou reaproveitado de uma
  # chamada anterior) -- nunca cria uma segunda instância para a mesma
  # (account, indice).
  #
  # A ponte já é idempotente por (tenant_id, indice) — repetir a chamada
  # devolve sempre o MESMO instance_name/api_url/api_key, nunca provisiona
  # um container novo. O que falta garantir deste lado é não criar um
  # segundo Channel::EvolutionApi/Inbox no Postgres do Chatwoot para essas
  # mesmas credenciais — por isso a ordem é sempre "pergunta à ponte
  # primeiro, só cria linha local se ainda não existir uma com esse nome".
  def call
    credentials = provision_on_bridge!

    existing = account.evolution_api_channels.find_by(instance_name: credentials.fetch('instance_name'))
    return existing.inbox if existing

    create_inbox!(credentials)
  end

  private

  attr_reader :account, :indice

  def provision_on_bridge!
    response = HTTParty.post(
      "#{bridge_url}/admin/evolution/provision",
      headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{bridge_admin_token}" },
      body: { chatwoot_account_id: account.id, indice: indice }.to_json,
      timeout: 180 # provisionamento real de container pode levar dezenas de segundos
    )
    raise ProvisioningError, "ponte indisponível: #{response.code}" unless response.success?

    response.parsed_response
  rescue StandardError => e
    raise e if e.is_a?(ProvisioningError)

    raise ProvisioningError, "falha ao provisionar instância WhatsApp: #{e.message}"
  end

  def create_inbox!(credentials)
    rotulo = indice > 1 ? " #{indice}" : ''
    inbox = nil
    ActiveRecord::Base.transaction do
      channel = account.evolution_api_channels.create!(
        instance_name: credentials.fetch('instance_name'),
        api_url: credentials.fetch('api_url'),
        api_key: credentials.fetch('api_key')
      )
      inbox = account.inboxes.create!(name: "WhatsApp (Evolution)#{rotulo}", channel: channel)
    end
    inbox
  end

  def bridge_url
    ENV.fetch('BRIDGE_URL') { raise ProvisioningError, 'BRIDGE_URL não configurada' }
  end

  def bridge_admin_token
    ENV.fetch('BRIDGE_ADMIN_TOKEN') { raise ProvisioningError, 'BRIDGE_ADMIN_TOKEN não configurado' }
  end
end
