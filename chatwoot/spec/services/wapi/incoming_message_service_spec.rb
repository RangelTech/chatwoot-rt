require 'rails_helper'

RSpec.describe Wapi::IncomingMessageService do
  let(:wapi_channel) { create(:channel_wapi) }
  let(:inbox) { wapi_channel.inbox }

  describe '#perform' do
    it 'creates a contact, conversation and incoming message from the payload' do
      params = { from: '5511999999999', text: 'ola', id: 'wapi-msg-1' }

      expect do
        described_class.new(inbox: inbox, params: params.with_indifferent_access).perform
      end.to change(Conversation, :count).by(1).and change(Message, :count).by(1)

      message = Message.last
      expect(message.content).to eq('ola')
      expect(message.message_type).to eq('incoming')
      expect(message.source_id).to eq('wapi-msg-1')
      expect(message.sender.phone_number).to eq('5511999999999')
    end

    it 'reuses the existing open conversation for the same contact instead of creating a new one' do
      params = { from: '5511999999999', text: 'primeira', id: 'wapi-msg-1' }
      described_class.new(inbox: inbox, params: params.with_indifferent_access).perform

      params2 = { from: '5511999999999', text: 'segunda', id: 'wapi-msg-2' }
      expect do
        described_class.new(inbox: inbox, params: params2.with_indifferent_access).perform
      end.to change(Message, :count).by(1).and change(Conversation, :count).by(0)
    end

    it 'is idempotent when the same provider message id arrives twice' do
      params = { from: '5511999999999', text: 'ola', id: 'wapi-msg-1' }
      described_class.new(inbox: inbox, params: params.with_indifferent_access).perform

      expect do
        described_class.new(inbox: inbox, params: params.with_indifferent_access).perform
      end.not_to change(Message, :count)
    end
  end
end
