require 'rails_helper'

RSpec.describe Evolution::DeprovisioningService do
  let(:account) { create(:account) }

  before do
    stub_const('ENV', ENV.to_hash.merge(
      'BRIDGE_URL' => 'https://bridge.example.test',
      'BRIDGE_ADMIN_TOKEN' => 'admin-token'
    ))
  end

  def stub_bridge(status: 200, body: { status: 'removed' })
    stub_request(:post, 'https://bridge.example.test/admin/evolution/deprovision')
      .with(
        headers: { 'Authorization' => 'Bearer admin-token' },
        body: { chatwoot_account_id: account.id, instance_name: 'evolution-abc123' }.to_json
      )
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # Achado real 25/08/2026: o serviço recebe account_id/instance_name
  # explícitos, não um `channel:` -- chamar `channel.inbox.account_id`
  # dentro de um before_destroy quebrava sempre, `channel.inbox` já vem
  # nil na cascata de destroy. Ver Inbox#deprovision_evolution_on_bridge!.
  it 'tells the bridge to tear down the real instance for this account/instance_name' do
    request = stub_bridge

    described_class.new(account_id: account.id, instance_name: 'evolution-abc123').call

    expect(request).to have_been_requested
  end

  it 'raises DeprovisioningError, not a raw HTTP failure, when the bridge rejects the request' do
    stub_bridge(status: 502, body: { detail: 'ssh falhou' })

    expect { described_class.new(account_id: account.id, instance_name: 'evolution-abc123').call }
      .to raise_error(described_class::DeprovisioningError)
  end

  it 'raises DeprovisioningError when the bridge is unreachable' do
    stub_request(:post, 'https://bridge.example.test/admin/evolution/deprovision').to_timeout

    expect { described_class.new(account_id: account.id, instance_name: 'evolution-abc123').call }
      .to raise_error(described_class::DeprovisioningError)
  end
end
