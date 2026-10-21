# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::SendOnUnofficialService do
  let(:channel) { create(:channel_whatsapp_unofficial) }
  let(:inbox) { channel.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: 'thread-77') }
  let(:conversation) do
    create(:conversation, inbox: inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact, account: inbox.account)
  end
  let(:message) do
    create(:message, conversation: conversation, inbox: inbox, account: inbox.account, message_type: :outgoing, content: 'oi')
  end
  let(:send_url) { gateway_url("/connections/#{channel.connection_id}/send") }

  around { |ex| with_gateway_env { ex.run } }

  it 'envia pelo gateway com idempotency_key = message.id e marca como entregue' do
    stub = stub_request(:post, send_url)
           .with(headers: { 'Authorization' => "Bearer #{ChannelsGatewayHelpers::GATEWAY_TOKEN}" }) do |req|
             body = JSON.parse(req.body)
             body['idempotency_key'] == message.id.to_s && body['conversation_ref'] == 'thread-77' && body['text'] == 'oi'
           end.to_return(status: 200, body: { outbox_id: 'o1', status: 'sent', external_id: 'ext-1' }.to_json)
    described_class.new(message: message).perform
    expect(stub).to have_been_requested.once
    expect(message.reload).to have_attributes(source_id: 'ext-1', status: 'delivered')
  end

  it 'status queued não marca entregue' do
    stub_request(:post, send_url).to_return(status: 200, body: { outbox_id: 'o1', status: 'queued' }.to_json)
    described_class.new(message: message).perform
    expect(message.reload.status).to eq('sent')
  end

  it 'falha do gateway marca failed com o código' do
    stub_request(:post, send_url).to_return(status: 502, body: { error_code: 'provider_unavailable' }.to_json)
    described_class.new(message: message).perform
    expect(message.reload).to have_attributes(status: 'failed', external_error: 'provider_unavailable')
  end

  it 'status failed na resposta marca failed' do
    stub_request(:post, send_url).to_return(status: 200, body: { status: 'failed', error_code: 'account_locked' }.to_json)
    described_class.new(message: message).perform
    expect(message.reload).to have_attributes(status: 'failed', external_error: 'account_locked')
  end

  it 'timeout de rede marca failed' do
    stub_request(:post, send_url).to_timeout
    described_class.new(message: message).perform
    expect(message.reload.status).to eq('failed')
  end

  it 'canal reauth_required não chama o gateway e falha' do
    channel.update!(state: 'reauth_required')
    described_class.new(message: message).perform
    expect(message.reload).to have_attributes(status: 'failed', external_error: 'channel_not_connected')
    expect(WebMock).not_to have_requested(:post, send_url)
  end

  it 'nota privada não sai' do
    note = create(:message, conversation: conversation, inbox: inbox, account: inbox.account, message_type: :outgoing, private: true)
    described_class.new(message: note).perform
    expect(WebMock).not_to have_requested(:post, send_url)
  end
end
