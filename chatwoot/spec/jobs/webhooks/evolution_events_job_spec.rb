require 'rails_helper'

RSpec.describe Webhooks::EvolutionEventsJob do
  let(:channel) { create(:channel_evolution_api, instance_name: 'tenant-one') }

  it 'persists the connection state from a provider webhook' do
    described_class.new.perform(instance_name: channel.instance_name, params: { event: 'CONNECTION_UPDATE', data: { state: 'open' } })

    expect(channel.reload.connection_status['state']).to eq('open')
    expect(channel.qr_code).to be_nil
  end

  it 'delegates inbound messages to the normal Chatwoot channel pipeline' do
    service = instance_double(Evolution::IncomingMessageService, perform: true)
    allow(Evolution::IncomingMessageService).to receive(:new).and_return(service)

    described_class.new.perform(instance_name: channel.instance_name, params: { event: 'MESSAGES_UPSERT', data: {} })

    expect(Evolution::IncomingMessageService).to have_received(:new).with(inbox: channel.inbox, params: hash_including('event' => 'MESSAGES_UPSERT'))
  end
end
