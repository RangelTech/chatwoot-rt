# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::IncomingMessageService do
  let(:channel) { create(:channel_instagram_unofficial) }
  let(:inbox) { channel.inbox }

  def run(event) = described_class.new(channel: channel, payload: event.deep_stringify_keys).perform

  it 'cria contato, conversa e mensagem com source_id = external_id' do
    run(gateway_message_event)
    msg = inbox.messages.last
    expect(msg).to have_attributes(source_id: 'm-1', content: 'olá', message_type: 'incoming')
    expect(msg.conversation.contact.name).to eq('Maria')
    expect(msg.conversation.contact_inbox.source_id).to eq('thread-1')
  end

  it 'é idempotente por external_id (0 duplicata)' do
    3.times { run(gateway_message_event) }
    expect(inbox.messages.where(source_id: 'm-1').count).to eq(1)
    expect(inbox.conversations.count).to eq(1)
  end

  it 'agrupa mensagens da mesma sala na mesma conversa' do
    run(gateway_message_event(external_id: 'a'))
    run(gateway_message_event(external_id: 'b'))
    expect(inbox.conversations.count).to eq(1)
    expect(inbox.messages.count).to eq(2)
  end

  it 'separa salas diferentes' do
    run(gateway_message_event(external_id: 'a', conversation: 't1'))
    run(gateway_message_event(external_id: 'b', conversation: 't2'))
    expect(inbox.conversations.count).to eq(2)
  end

  it 'ignora eventos sem external_id' do
    expect { run(gateway_message_event(external_id: '')) }.not_to(change { inbox.messages.count })
  end

  describe 'eco de saída (outgoing_echo)' do
    let!(:conversation) do
      run(gateway_message_event(external_id: 'in-1'))
      inbox.conversations.last
    end

    def own_message
      create(:message, conversation: conversation, inbox: inbox, account: inbox.account, message_type: :outgoing, content: 'resposta')
    end

    it 'adota o external_id da mensagem enviada por nós sem duplicar' do
      ours = own_message
      expect { run(gateway_message_event(external_id: 'out-9', text: 'resposta', direction: 'outgoing_echo')) }.not_to(change { inbox.messages.count })
      expect(ours.reload.source_id).to eq('out-9')
    end

    it 'eco repetido depois de adotado também não duplica' do
      own_message
      2.times { run(gateway_message_event(external_id: 'out-9', text: 'resposta', direction: 'outgoing_echo')) }
      expect(inbox.messages.where(source_id: 'out-9').count).to eq(1)
    end

    it 'eco de mensagem enviada pelo aplicativo nativo vira outgoing com source_id e não é reenviada' do
      run(gateway_message_event(external_id: 'out-10', text: 'pelo celular', direction: 'outgoing_echo'))
      msg = inbox.messages.find_by(source_id: 'out-10')
      expect(msg.message_type).to eq('outgoing')
      expect(Channels::SendOnUnofficialService.new(message: msg).perform).to be_nil
    end
  end

  describe 'connection.state' do
    it 'atualiza estado, erro e atividade' do
      run(type: 'connection.state', occurred_at: '2026-10-20T10:00:00Z', state: { state: 'reauth_required', error_code: 'wrong_password' })
      expect(channel.reload).to have_attributes(state: 'reauth_required', last_error_code: 'wrong_password')
      expect(channel.last_activity_at).to eq(Time.zone.parse('2026-10-20T10:00:00Z'))
    end
  end

  describe 'message.status' do
    it 'atualiza o status da mensagem pelo external_id' do
      run(gateway_message_event(external_id: 'x'))
      msg = inbox.messages.find_by(source_id: 'x')
      run(type: 'message.status', message: { external_id: 'x', status: 'read' })
      expect(msg.reload.status).to eq('read')
    end
  end

  describe 'anexos' do
    let(:base) { "#{ChannelsGatewayHelpers::GATEWAY_URL}/internal/channels/attachments" }

    it 'baixa da URL assinada do gateway e anexa' do
      with_gateway_env do
        stub_request(:get, "#{base}/tok1")
          .with(headers: { 'Authorization' => "Bearer #{ChannelsGatewayHelpers::GATEWAY_TOKEN}" })
          .to_return(status: 200, body: 'PNGDATA', headers: { 'Content-Type' => 'image/png' })
        att = { kind: 'image', mime: 'image/png', name: 'a.png', url: "#{base}/tok1" }
        run(gateway_message_event(external_id: 'img', text: '', attachments: [att]))
        attachment = inbox.messages.find_by(source_id: 'img').attachments.first
        expect(attachment).to have_attributes(file_type: 'image')
        expect(attachment.file.download).to eq('PNGDATA')
      end
    end

    it 'recusa URL fora do gateway (SSRF) mas mantém a mensagem' do
      with_gateway_env do
        att = { kind: 'image', mime: 'image/png', name: 'a.png', url: 'http://evil.test/x' }
        run(gateway_message_event(external_id: 'img2', text: 'oi', attachments: [att]))
        msg = inbox.messages.find_by(source_id: 'img2')
        expect(msg).to be_present
        expect(msg.attachments).to be_empty
        expect(a_request(:get, 'http://evil.test/x')).not_to have_been_made
      end
    end
  end
end
