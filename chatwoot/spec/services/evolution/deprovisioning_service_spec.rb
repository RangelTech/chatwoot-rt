require 'rails_helper'

RSpec.describe Evolution::DeprovisioningService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_evolution_api, account: account, instance_name: 'evolution-abc123') }

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

  it 'tells the bridge to tear down the real instance for this channel' do
    request = stub_bridge

    described_class.new(channel: channel).call

    expect(request).to have_been_requested
  end

  it 'raises DeprovisioningError, not a raw HTTP failure, when the bridge rejects the request' do
    stub_bridge(status: 502, body: { detail: 'ssh falhou' })

    expect { described_class.new(channel: channel).call }
      .to raise_error(described_class::DeprovisioningError)
  end

  it 'raises DeprovisioningError when the bridge is unreachable' do
    stub_request(:post, 'https://bridge.example.test/admin/evolution/deprovision').to_timeout

    expect { described_class.new(channel: channel).call }
      .to raise_error(described_class::DeprovisioningError)
  end
end
