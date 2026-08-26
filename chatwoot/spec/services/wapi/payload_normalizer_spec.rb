require 'rails_helper'

RSpec.describe Wapi::PayloadNormalizer do
  # Achado real 24/08/2026 (produto-09): este é o formato REAL do payload
  # (confirmado contra webhook de verdade do WAPI, `event: "webhookReceived"`)
  # -- os specs antigos deste job/controller ainda testavam contra o formato
  # especulativo antigo (`type: 'message', message: {from, text, id}`), que
  # nunca bateu com produção. Este spec cobre o formato real, pra não deixar
  # a correção sem regressão.
  let(:payload_real) do
    {
      event: 'webhookReceived',
      instanceId: 'inst-123',
      isGroup: false,
      fromMe: false,
      chat: { id: '5511999999999@c.us' },
      sender: { id: '5511999999999@c.us', senderLid: 'lid-123', pushName: 'Cliente Teste' },
      messageId: 'msg-real-1',
      msgContent: { conversation: 'Olá, quero fazer um pedido' }
    }
  end

  describe '#message?' do
    it 'reconhece uma mensagem real recebida (fromMe: false)' do
      expect(described_class.new(payload_real).message?).to be true
    end

    it 'nunca trata a própria resposta do agente (fromMe: true) como mensagem nova -- evitaria eco infinito' do
      eco = payload_real.merge(fromMe: true)
      expect(described_class.new(eco).message?).to be false
    end

    it 'não confunde payload vazio/desconhecido com mensagem' do
      expect(described_class.new({}).message?).to be false
    end
  end

  describe '#message' do
    it 'extrai remetente, texto, id e nome do formato real' do
      resultado = described_class.new(payload_real).message
      expect(resultado).to include(
        from: '5511999999999@c.us',
        text: 'Olá, quero fazer um pedido',
        id: 'msg-real-1',
        name: 'Cliente Teste'
      )
    end
  end

  describe '#connection_event?' do
    it 'não confunde uma mensagem real com evento de conexão' do
      expect(described_class.new(payload_real).connection_event?).to be false
    end

    it 'reconhece connection_update' do
      evento = { event: 'connection_update', connected: true }
      expect(described_class.new(evento).connection_event?).to be true
    end
  end
end
