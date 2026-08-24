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

  def initialize(account:, indice: nil, name: nil)
    @account = account
    @indice = indice
    @name = name.to_s.strip.presence
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
  #
  # Achado real 24/08/2026: `indice` nunca era passado pelo controller,
  # ficava sempre no default 1 -- criar uma "segunda" conexão Evolution
  # no mesmo tenant sempre resolvia pro MESMO instance_name na ponte, e
  # este `find_by` sempre achava o canal já existente e devolvia a MESMA
  # inbox, nunca criava uma nova. Não era o nome do inbox, era o índice
  # nunca variar. Agora, sem `indice` explícito, o próximo é derivado do
  # número de conexões Evolution que a conta já tem -- seguro porque
  # canal local e provisionamento na ponte sempre nascem juntos (mesma
  # transação), nunca ficam dessincronizados nesse sentido.
  def call
    @indice ||= account.evolution_api_channels.count + 1
    credentials = provision_on_bridge!

    existing = account.evolution_api_channels.find_by(instance_name: credentials.fetch('instance_name'))
    return existing.inbox if existing

    create_inbox!(credentials)
  end

  private

  attr_reader :account, :indice, :name

  def provision_on_bridge!
    response = HTTParty.post(
      "#{bridge_url}/admin/evolution/provision",
      headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{bridge_admin_token}" },
      body: { chatwoot_account_id: account.id, indice: indice }.to_json,
      # Achado real 24/08/2026 (testado ao vivo com provisionamento do zero,
      # não idempotente): pior caso da ponte é ~40s de espera do Postgres
      # (20 tentativas x 2s) + até 120s de health check (40 tentativas x 3s)
      # + overhead de várias chamadas SSH sequenciais -- passa de 180s sem
      # exagero, não é hipotético. 240s dá margem de verdade acima do pior
      # caso calculado da ponte (~180-200s), sem inflar demais.
      timeout: 240
    )
    raise ProvisioningError, "ponte indisponível: #{response.code}" unless response.success?

    response.parsed_response
  rescue StandardError => e
    raise e if e.is_a?(ProvisioningError)

    raise ProvisioningError, "falha ao provisionar instância WhatsApp: #{e.message}"
  end

  def create_inbox!(credentials)
    rotulo = indice > 1 ? " #{indice}" : ''
    inbox_name = name || "WhatsApp (Evolution)#{rotulo}"
    inbox = nil
    ActiveRecord::Base.transaction do
      channel = account.evolution_api_channels.create!(
        instance_name: credentials.fetch('instance_name'),
        api_url: credentials.fetch('api_url'),
        api_key: credentials.fetch('api_key')
      )
      inbox = account.inboxes.create!(name: inbox_name, channel: channel)
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
