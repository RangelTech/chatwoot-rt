require 'rails_helper'

RSpec.describe Evolution::IncomingMessageService do
  let(:channel) { create(:channel_evolution_api) }
  let(:inbox) { channel.inbox }

  def payload(text:, message_id:, remote_jid: '556285613482@s.whatsapp.net', from_me: false)
    {
      key: { remoteJid: remote_jid, fromMe: from_me, id: message_id },
      pushName: 'Lucas Rangel',
      message: { conversation: text }
    }
  end

  describe '#perform' do
    # Achado real 24/08/2026, testado ao vivo: sem o "+", Contact#phone_number
    # falhava a validação E164 ("Phone number should be in e164 format") e o
    # job do webhook quebrava silenciosamente -- nenhuma conversa era criada,
    # mesmo com o resto do pipeline (evento, roteamento) já corrigido.
    it 'creates a contact, conversation and incoming message with an E.164 phone number' do
      params = { data: payload(text: 'ola', message_id: 'msg-1') }

      expect do
        described_class.new(inbox: inbox, params: params.with_indifferent_access).perform
      end.to change(Conversation, :count).by(1).and change(Message, :count).by(1)

      message = Message.last
      expect(message.content).to eq('ola')
      expect(message.message_type).to eq('incoming')
      expect(message.source_id).to eq('msg-1')
      expect(message.sender.phone_number).to eq('+556285613482')
    end

    it 'reuses the existing open conversation for the same contact instead of creating a new one' do
      described_class.new(
        inbox: inbox, params: { data: payload(text: 'primeira', message_id: 'msg-1') }.with_indifferent_access
      ).perform

      expect do
        described_class.new(
          inbox: inbox, params: { data: payload(text: 'segunda', message_id: 'msg-2') }.with_indifferent_access
        ).perform
      end.to change(Message, :count).by(1).and change(Conversation, :count).by(0)
    end

    it 'is idempotent when the same provider message id arrives twice' do
      params = { data: payload(text: 'ola', message_id: 'msg-1') }
      described_class.new(inbox: inbox, params: params.with_indifferent_access).perform

      expect do
        described_class.new(inbox: inbox, params: params.with_indifferent_access).perform
      end.not_to change(Message, :count)
    end

    it 'ignores messages the connected account itself sent (fromMe: true)' do
      params = { data: payload(text: 'oi', message_id: 'msg-1', from_me: true) }

      expect do
        described_class.new(inbox: inbox, params: params.with_indifferent_access).perform
      end.not_to change(Message, :count)
    end
  end
end
