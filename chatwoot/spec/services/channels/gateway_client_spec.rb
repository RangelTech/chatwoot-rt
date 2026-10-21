# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::GatewayClient do
  around { |ex| with_gateway_env { ex.run } }

  let(:client) { described_class.new(account_id: 7) }
  let(:id) { SecureRandom.uuid }

  it 'envia token e account_id e devolve hash indiferente' do
    stub = stub_request(:get, gateway_url('/catalog'))
           .with(headers: { 'Authorization' => 'Bearer gw-token-test', 'X-Luar-Account-Id' => '7' })
           .to_return(status: 200, body: { providers: [] }.to_json)
    expect(client.catalog[:providers]).to eq([])
    expect(stub).to have_been_requested
  end

  it 'erro traz só o código, nunca o corpo da requisição' do
    stub_request(:post, gateway_url("/connections/#{id}/step")).to_return(status: 422, body: { error_code: 'wrong_password' }.to_json)
    expect { client.step(id, step_id: 's', kind: 'credentials', data: { password: 'SENHA-SECRETA' }) }
      .to raise_error(described_class::Error) { |e|
        expect(e.code).to eq('wrong_password')
        expect(e.message).not_to include('SENHA-SECRETA')
      }
  end

  it '429 vira too_many_attempts' do
    stub_request(:post, gateway_url('/connections')).to_return(status: 429, body: '{}')
    expect { client.create_connection(account_id: 7, provider: 'instagram', actor_id: 1, consent: { accepted: true }) }
      .to raise_error(described_class::Error) { |e| expect(e.code).to eq('too_many_attempts') }
  end

  it 'resposta inválida e rede fora viram provider_unavailable' do
    stub_request(:get, gateway_url('/catalog')).to_return(status: 200, body: 'nao-json')
    expect { client.catalog }.to raise_error(described_class::Error) { |e| expect(e.code).to eq('provider_unavailable') }
    stub_request(:get, gateway_url('/catalog')).to_raise(Errno::ECONNREFUSED)
    expect { client.catalog }.to raise_error(described_class::Error) { |e| expect(e.code).to eq('provider_unavailable') }
  end

  it 'rejeita id com caracteres de caminho' do
    expect { client.show('../etc/passwd') }.to raise_error(described_class::Error)
  end

  it 'sem configuração, falha sem rede' do
    ENV['CHANNELS_GATEWAY_URL'] = nil
    expect { client.catalog }.to raise_error(described_class::Error)
  end
end
