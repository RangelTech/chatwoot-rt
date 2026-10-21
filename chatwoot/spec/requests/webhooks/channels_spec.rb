# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Webhooks::ChannelsController', type: :request do
  let(:channel) { create(:channel_instagram_unofficial) }
  let(:secret) { channel.webhook_secret }
  let(:path) { "/webhooks/channels/instagram_unofficial/#{channel.id}" }
  let(:body) { message_event.to_json }

  after { Redis::Alfred.scan_each(match: 'channels:webhook:*') { |k| Redis::Alfred.delete(k) } }

  def deliver(headers, raw = body)
    post path, params: raw, headers: headers
  end

  it 'aceita assinatura válida e cria a mensagem na caixa' do
    expect { deliver(signed_headers(secret, body)) }.to change { channel.inbox.messages.count }.by(1)
    expect(response).to have_http_status(:ok)
    expect(channel.inbox.messages.last).to have_attributes(source_id: 'm-1', content: 'olá', message_type: 'incoming')
  end

  it 'rejeita assinatura inválida' do
    deliver(signed_headers(secret, body, signature: 'sha256=deadbeef'))
    expect(response).to have_http_status(:unauthorized)
    expect(channel.inbox.messages.count).to eq(0)
  end

  it 'rejeita assinatura feita com outro segredo' do
    deliver(signed_headers('outro-segredo', body))
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejeita corpo adulterado' do
    headers = signed_headers(secret, body)
    deliver(headers, message_event(text: 'adulterado').to_json)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejeita timestamp velho (> 300 s) e futuro' do
    deliver(signed_headers(secret, body, timestamp: Time.now.to_i - 301))
    expect(response).to have_http_status(:unauthorized)
    deliver(signed_headers(secret, body, timestamp: Time.now.to_i + 301))
    expect(response).to have_http_status(:unauthorized)
  end

  it 'aceita timestamp dentro da tolerância' do
    deliver(signed_headers(secret, body, timestamp: Time.now.to_i - 290))
    expect(response).to have_http_status(:ok)
  end

  it 'rejeita cabeçalhos ausentes' do
    post path, params: body, headers: { 'CONTENT_TYPE' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'bloqueia replay do mesmo event_id' do
    deliver(signed_headers(secret, body, event_id: 'ev-1'))
    expect(response).to have_http_status(:ok)
    deliver(signed_headers(secret, body, event_id: 'ev-1'))
    expect(response).to have_http_status(:conflict)
    expect(channel.inbox.messages.count).to eq(1)
  end

  it 'libera o event_id se o processamento falhar (permite retry do gateway)' do
    allow_any_instance_of(Channels::IncomingMessageService).to receive(:perform).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance
    expect { deliver(signed_headers(secret, body, event_id: 'ev-2')) }.to raise_error(StandardError, 'boom')
    expect(Redis::Alfred.exists?("channels:webhook:Channel::InstagramUnofficial:#{channel.id}:ev-2")).to be(false)
  end

  it 'retorna 404 para canal ou tipo inexistente' do
    post '/webhooks/channels/instagram_unofficial/0', params: body, headers: signed_headers(secret, body)
    expect(response).to have_http_status(:not_found)
    post "/webhooks/channels/wapi/#{channel.id}", params: body, headers: signed_headers(secret, body)
    expect(response).to have_http_status(:not_found)
  end

  it 'não aceita assinatura de um canal em outro (cross-tenant)' do
    other = create(:channel_instagram_unofficial)
    post "/webhooks/channels/instagram_unofficial/#{other.id}", params: body, headers: signed_headers(secret, body)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'canal sem segredo nunca autentica' do
    channel.update_columns(webhook_secret: nil) # rubocop:disable Rails/SkipsModelValidations
    deliver(signed_headers('', body))
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejeita corpo que não é JSON objeto' do
    raw = '[1,2]'
    deliver(signed_headers(secret, raw), raw)
    expect(response).to have_http_status(:bad_request)
  end

  it 'connection.state atualiza o estado do canal' do
    raw = { type: 'connection.state', occurred_at: Time.current.iso8601, state: { state: 'degraded', error_code: 'timeout' } }.to_json
    deliver(signed_headers(secret, raw), raw)
    expect(response).to have_http_status(:ok)
    expect(channel.reload).to have_attributes(state: 'degraded', last_error_code: 'timeout')
  end
end
