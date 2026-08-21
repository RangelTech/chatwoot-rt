require 'rails_helper'

RSpec.describe Channel::EvolutionApi do
  it 'requires the managed instance configuration' do
    channel = described_class.new

    expect(channel).not_to be_valid
    expect(channel.errors).to include(:instance_name, :api_url, :api_key)
  end

  it 'creates an opaque webhook token and exposes it only in the callback URL' do
    channel = create(:channel_evolution_api, instance_name: 'tenant-one')

    expect(channel.webhook_verify_token).to be_present
    expect(channel.callback_url).to include('/webhooks/evolution/tenant-one?verify_token=')
  end

  it 'persists the QR and connection state returned by the provider client' do
    channel = create(:channel_evolution_api)
    allow(Evolution::Client).to receive(:new).with(channel: channel).and_return(
      instance_double(Evolution::Client, connect: { qr_code: 'data:image/png;base64,abc', connection_status: { 'state' => 'connecting' } })
    )

    channel.connect!

    expect(channel.reload.qr_code).to eq('data:image/png;base64,abc')
    expect(channel.connection_status).to eq({ 'state' => 'connecting' })
  end
end
