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

  # Achado real 24/08/2026: apagar a inbox nunca desligava a instância real
  # na VPS -- reconectar reaproveitava a mesma sessão WhatsApp já logada.
  it 'deprovisions the real instance on the bridge before destroying the channel' do
    channel = create(:channel_evolution_api)
    service = instance_double(Evolution::DeprovisioningService, call: true)
    allow(Evolution::DeprovisioningService).to receive(:new).with(channel: channel).and_return(service)

    channel.destroy!

    expect(service).to have_received(:call)
    expect(Channel::EvolutionApi.exists?(channel.id)).to be false
  end

  it 'blocks destruction when the bridge cannot be reached, keeping the channel around to retry' do
    channel = create(:channel_evolution_api)
    service = instance_double(Evolution::DeprovisioningService)
    allow(Evolution::DeprovisioningService).to receive(:new).with(channel: channel).and_return(service)
    allow(service).to receive(:call).and_raise(Evolution::DeprovisioningService::DeprovisioningError, 'ponte indisponível: 502')

    expect { channel.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(Channel::EvolutionApi.exists?(channel.id)).to be true
  end
end
