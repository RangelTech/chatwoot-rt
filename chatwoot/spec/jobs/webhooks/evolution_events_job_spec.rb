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

  describe 'MESSAGES_UPDATE' do
    let(:conversation) { create(:conversation, inbox: channel.inbox, account: channel.inbox.account) }
    let(:message) do
      create(:message, conversation: conversation, account: conversation.account, source_id: 'wamid-123',
                        message_type: :outgoing, status: :sent)
    end

    it 'marks an outgoing message as delivered on DELIVERY_ACK' do
      described_class.new.perform(
        instance_name: channel.instance_name,
        params: { event: 'MESSAGES_UPDATE', data: { fromMe: true, messageId: message.source_id, status: 'DELIVERY_ACK' } }
      )

      expect(message.reload.status).to eq('delivered')
    end

    it 'marks an outgoing message as read on READ' do
      described_class.new.perform(
        instance_name: channel.instance_name,
        params: { event: 'MESSAGES_UPDATE', data: { fromMe: true, messageId: message.source_id, status: 'READ' } }
      )

      expect(message.reload.status).to eq('read')
    end

    it 'ignores updates for messages we received (fromMe: false)' do
      described_class.new.perform(
        instance_name: channel.instance_name,
        params: { event: 'MESSAGES_UPDATE', data: { fromMe: false, messageId: message.source_id, status: 'READ' } }
      )

      expect(message.reload.status).to eq('sent')
    end

    it 'does nothing when no message matches the source_id' do
      expect do
        described_class.new.perform(
          instance_name: channel.instance_name,
          params: { event: 'MESSAGES_UPDATE', data: { fromMe: true, messageId: 'unknown-id', status: 'READ' } }
        )
      end.not_to raise_error
    end
  end
end
