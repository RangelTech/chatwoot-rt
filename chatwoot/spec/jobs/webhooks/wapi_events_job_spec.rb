require 'rails_helper'

RSpec.describe Webhooks::WapiEventsJob do
  let(:channel) { create(:channel_wapi, project_id: 'proj-123') }

  describe '#perform' do
    context 'when no channel matches the project_id' do
      it 'does nothing' do
        expect { described_class.new.perform(project_id: 'missing', params: { type: 'message' }) }.not_to raise_error
      end
    end

    context 'with a message event' do
      it 'delegates to Wapi::IncomingMessageService' do
        service = instance_double(Wapi::IncomingMessageService, perform: true)
        allow(Wapi::IncomingMessageService).to receive(:new).and_return(service)

        described_class.new.perform(
          project_id: channel.project_id,
          params: { type: 'message', message: { from: '5511999999999', text: 'oi', id: 'msg-1' } }
        )

        expect(Wapi::IncomingMessageService).to have_received(:new).with(
          inbox: channel.inbox,
          params: hash_including('from' => '5511999999999', 'text' => 'oi')
        )
        expect(service).to have_received(:perform)
      end
    end

    context 'with a connection_update event' do
      it 'updates the channel connection_status to connected' do
        described_class.new.perform(project_id: channel.project_id, params: { type: 'connection_update', status: 'connected' })

        expect(channel.reload.connection_status['status']).to eq('connected')
        expect(channel.reload.connection_status_checked_at).to be_present
      end

      it 'updates the channel connection_status to disconnected for any other status value' do
        described_class.new.perform(project_id: channel.project_id, params: { type: 'connection_update', status: 'closed' })

        expect(channel.reload.connection_status['status']).to eq('disconnected')
      end
    end
  end
end
