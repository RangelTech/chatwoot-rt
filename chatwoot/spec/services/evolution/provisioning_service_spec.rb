require 'rails_helper'

RSpec.describe Evolution::ProvisioningService do
  let(:account) { create(:account) }

  before do
    stub_const('ENV', ENV.to_hash.merge(
      'BRIDGE_URL' => 'https://bridge.example.test',
      'BRIDGE_ADMIN_TOKEN' => 'admin-token'
    ))
  end

  def stub_bridge(status: 200, body: {})
    stub_request(:post, 'https://bridge.example.test/admin/evolution/provision')
      .with(
        headers: { 'Authorization' => 'Bearer admin-token' },
        body: { chatwoot_account_id: account.id, indice: 1 }.to_json
      )
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'never sends a tenant_id -- only the authenticated account id' do
    request = stub_bridge(body: {
      status: 'ready', instance_name: 'evolution-abc123', api_url: 'https://evolution-abc.example', api_key: 'k'
    })

    described_class.new(account: account).call

    expect(request).to have_been_requested
  end

  it 'creates the inbox with credentials it never exposes back to the caller' do
    stub_bridge(body: {
      status: 'ready', instance_name: 'evolution-abc123', api_url: 'https://evolution-abc.example', api_key: 'secret-key'
    })

    inbox = described_class.new(account: account).call

    expect(inbox).to be_a(Inbox)
    expect(inbox.account_id).to eq(account.id)
    channel = inbox.channel
    expect(channel.instance_name).to eq('evolution-abc123')
    expect(channel.api_key).to eq('secret-key')
  end

  it 'uses the admin-provided name for the inbox, falling back to the default when blank' do
    stub_bridge(body: {
      status: 'ready', instance_name: 'evolution-abc123', api_url: 'https://evolution-abc.example', api_key: 'k'
    })

    inbox = described_class.new(account: account, name: '  joaopedro  ').call

    expect(inbox.name).to eq('joaopedro')
  end

  it 'is idempotent: calling twice for the same account never creates a second inbox' do
    stub_bridge(body: {
      status: 'ready', instance_name: 'evolution-abc123', api_url: 'https://evolution-abc.example', api_key: 'k'
    })

    first = described_class.new(account: account).call
    second = described_class.new(account: account).call

    expect(second.id).to eq(first.id)
    expect(account.evolution_api_channels.count).to eq(1)
    expect(account.inboxes.where(name: 'WhatsApp (Evolution)').count).to eq(1)
  end

  it 'raises ProvisioningError, not a raw HTTP failure, when the bridge is unreachable' do
    stub_request(:post, 'https://bridge.example.test/admin/evolution/provision').to_timeout

    expect { described_class.new(account: account).call }
      .to raise_error(described_class::ProvisioningError)
  end

  it 'raises ProvisioningError when the bridge rejects the request' do
    stub_bridge(status: 502, body: { detail: 'provisionamento falhou' })

    expect { described_class.new(account: account).call }
      .to raise_error(described_class::ProvisioningError)
  end
end
