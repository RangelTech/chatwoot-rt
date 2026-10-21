# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::ChannelConnections', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:conn_id) { SecureRandom.uuid }
  let(:base) { "/api/v1/accounts/#{account.id}/channel_connections" }

  around { |ex| with_gateway_env { ex.run } }

  def connection_view(overrides = {})
    { id: conn_id, account_id: account.id, provider: 'instagram', mode: 'experimental', state: 'pending_auth',
      external_label: 'maria', connector_version: 'ig-v26.10' }.merge(overrides)
  end

  def step_view = { kind: 'credentials', step_id: 's1', fields: [{ id: 'password', type: 'password', secret: true }] }

  describe 'autorização' do
    it 'exige login' do
      get "#{base}/catalog"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'agente (não admin) é negado em todas as ações' do
      post base, headers: agent.create_new_auth_token, params: { provider: 'instagram', consent: true }, as: :json
      expect(response).to have_http_status(:unauthorized)
      get "#{base}/catalog", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/#{conn_id}/step", headers: agent.create_new_auth_token, params: { step_id: 'x', kind: 'credentials' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(WebMock).not_to have_requested(:any, /gateway.test/)
    end

    it 'admin de outra conta não acessa a conta alheia' do
      get "#{base}/catalog", headers: other_admin.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET catalog' do
    it 'repassa o catálogo do gateway' do
      stub_request(:get, gateway_url('/catalog')).to_return(status: 200, body: { providers: [{ provider: 'instagram' }], risk_notice_version: 'v1' }.to_json)
      get "#{base}/catalog", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['risk_notice_version']).to eq('v1')
    end

    it '503 quando o gateway não está configurado' do
      ENV['CHANNELS_GATEWAY_TOKEN'] = nil
      get "#{base}/catalog", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:service_unavailable)
    end
  end

  describe 'POST create' do
    it 'exige consentimento explícito' do
      post base, headers: admin.create_new_auth_token, params: { provider: 'instagram' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('consent_required')
      expect(WebMock).not_to have_requested(:post, gateway_url('/connections'))
    end

    it 'rejeita provedor desconhecido' do
      post base, headers: admin.create_new_auth_token, params: { provider: 'orkut', consent: true }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'cria a conexão no gateway com account_id do token (nunca do corpo)' do
      stub_request(:get, gateway_url('/catalog')).to_return(status: 200, body: { risk_notice_version: 'v1' }.to_json)
      stub = stub_request(:post, gateway_url('/connections')).with do |req|
        b = JSON.parse(req.body)
        b['account_id'] == account.id && b['provider'] == 'instagram' && b['actor_id'] == admin.id &&
          b['consent'] == { 'accepted' => true, 'version' => 'v1' }
      end.to_return(status: 201, body: { connection: connection_view, step: step_view }.to_json)
      post base, headers: admin.create_new_auth_token, params: { provider: 'instagram', consent: true, account_id: 999 }, as: :json
      expect(response).to have_http_status(:created)
      expect(stub).to have_been_requested
      expect(response.parsed_body.dig('connection', 'id')).to eq(conn_id)
      expect(response.parsed_body.dig('step', 'kind')).to eq('credentials')
    end

    it 'propaga too_many_attempts como 429' do
      stub_request(:get, gateway_url('/catalog')).to_return(status: 200, body: '{}')
      stub_request(:post, gateway_url('/connections')).to_return(status: 429, body: { error_code: 'too_many_attempts' }.to_json)
      post base, headers: admin.create_new_auth_token, params: { provider: 'instagram', consent: true }, as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error_code']).to eq('too_many_attempts')
    end
  end

  describe 'POST step' do
    it 'repassa a senha só ao gateway, sem job e sem eco na resposta' do
      stub = stub_request(:post, gateway_url("/connections/#{conn_id}/step")).with do |req|
        JSON.parse(req.body).dig('data', 'password') == 'SenhaSuperSecreta'
      end.to_return(status: 200, body: { state: 'awaiting_2fa', step: { kind: 'code_2fa', step_id: 's2' } }.to_json)
      expect do
        post "#{base}/#{conn_id}/step", headers: admin.create_new_auth_token, as: :json,
                                        params: { step_id: 's1', kind: 'credentials', data: { username: 'maria', password: 'SenhaSuperSecreta' } }
      end.not_to have_enqueued_job
      expect(stub).to have_been_requested
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('SenhaSuperSecreta')
      expect(response.parsed_body['connection']).to include('state' => 'awaiting_2fa')
    end

    it 'não escreve a senha no log' do
      stub_request(:post, gateway_url("/connections/#{conn_id}/step")).to_return(status: 422, body: { error_code: 'wrong_password' }.to_json)
      io = StringIO.new
      old = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      begin
        post "#{base}/#{conn_id}/step", headers: admin.create_new_auth_token, as: :json,
                                        params: { step_id: 's1', kind: 'credentials', data: { username: 'maria', password: 'SenhaNoLog123' } }
      ensure
        Rails.logger = old
      end
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error_code']).to eq('wrong_password')
      expect(io.string).not_to include('SenhaNoLog123')
    end

    it 'conexão de outro tenant devolve 404 (gateway)' do
      stub_request(:post, gateway_url("/connections/#{conn_id}/step")).to_return(status: 404, body: { error_code: 'not_found' }.to_json)
      post "#{base}/#{conn_id}/step", headers: admin.create_new_auth_token, as: :json, params: { step_id: 's1', kind: 'credentials', data: {} }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET show' do
    it 'devolve conexão e passo' do
      stub_request(:get, gateway_url("/connections/#{conn_id}")).to_return(status: 200, body: { connection: connection_view, step: step_view }.to_json)
      get "#{base}/#{conn_id}", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['connection']['state']).to eq('pending_auth')
    end

    it 'se o gateway devolver conexão de outra conta, Rails responde 404' do
      stub_request(:get, gateway_url("/connections/#{conn_id}"))
        .to_return(status: 200, body: { connection: connection_view(account_id: other_account.id) }.to_json)
      get "#{base}/#{conn_id}", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('maria')
    end
  end

  describe 'cancel, disconnect, revoke, reauth' do
    %w[cancel disconnect revoke reauth].each do |action|
      it "#{action} repassa ao gateway" do
        stub = stub_request(:post, gateway_url("/connections/#{conn_id}/#{action}"))
               .to_return(status: 200, body: { connection: connection_view(state: 'disconnected') }.to_json)
        post "#{base}/#{conn_id}/#{action}", headers: admin.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(stub).to have_been_requested
      end
    end

    it 'revoke atualiza o estado do canal existente' do
      channel = create(:channel_instagram_unofficial, account: account, connection_id: conn_id)
      stub_request(:post, gateway_url("/connections/#{conn_id}/revoke"))
        .to_return(status: 200, body: { connection: connection_view(state: 'revoked') }.to_json)
      post "#{base}/#{conn_id}/revoke", headers: admin.create_new_auth_token
      expect(channel.reload.state).to eq('revoked')
    end

    it 'não altera canal de outra conta com o mesmo connection_id' do
      channel = create(:channel_instagram_unofficial, account: other_account, connection_id: conn_id)
      stub_request(:post, gateway_url("/connections/#{conn_id}/revoke"))
        .to_return(status: 200, body: { connection: connection_view(state: 'revoked') }.to_json)
      post "#{base}/#{conn_id}/revoke", headers: admin.create_new_auth_token
      expect(channel.reload.state).to eq('connected')
    end
  end

  describe 'POST finalize' do
    let(:finalize_params) { { name: 'Insta da loja', sync_since_days: 30 } }

    def stub_connected(overrides = {})
      stub_request(:get, gateway_url("/connections/#{conn_id}"))
        .to_return(status: 200, body: { connection: connection_view({ state: 'connected' }.merge(overrides)) }.to_json)
    end

    it 'cria canal e caixa, registra delivery assinado e sincroniza' do
      stub_connected
      delivery = stub_request(:put, gateway_url("/connections/#{conn_id}/delivery")).with do |req|
        b = JSON.parse(req.body)
        b['webhook_url'].match?(%r{/webhooks/channels/instagram_unofficial/\d+\z}) && b['webhook_secret'].match?(/\A\h{64}\z/) && b['inbox_ref'].present?
      end.to_return(status: 200, body: '{}')
      sync = stub_request(:post, gateway_url("/connections/#{conn_id}/sync")).with { |req| JSON.parse(req.body)['since_days'] == 30 }
                                                                              .to_return(status: 200, body: { job_id: 'j' }.to_json)
      expect { post "#{base}/#{conn_id}/finalize", headers: admin.create_new_auth_token, params: finalize_params, as: :json }
        .to change(account.inboxes, :count).by(1)
      expect(response).to have_http_status(:ok)
      channel = Channel::InstagramUnofficial.find_by(connection_id: conn_id)
      expect(channel).to have_attributes(account_id: account.id, state: 'connected', connector_version: 'ig-v26.10')
      expect(channel.inbox.name).to eq('Insta da loja')
      expect(delivery).to have_been_requested
      expect(sync).to have_been_requested
      expect(response.body).not_to include(channel.webhook_secret)
    end

    it 'é idempotente: segunda chamada devolve a mesma caixa' do
      stub_connected
      stub_request(:put, gateway_url("/connections/#{conn_id}/delivery")).to_return(status: 200, body: '{}')
      stub_request(:post, gateway_url("/connections/#{conn_id}/sync")).to_return(status: 200, body: '{}')
      2.times { post "#{base}/#{conn_id}/finalize", headers: admin.create_new_auth_token, params: finalize_params, as: :json }
      expect(Channel::InstagramUnofficial.where(connection_id: conn_id).count).to eq(1)
    end

    it 'não finaliza conexão que não está conectada' do
      stub_connected(state: 'awaiting_2fa')
      post "#{base}/#{conn_id}/finalize", headers: admin.create_new_auth_token, params: finalize_params, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Channel::InstagramUnofficial.count).to eq(0)
    end

    it 'não finaliza conexão de outra conta' do
      stub_connected(account_id: other_account.id)
      post "#{base}/#{conn_id}/finalize", headers: admin.create_new_auth_token, params: finalize_params, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Channel::InstagramUnofficial.count).to eq(0)
    end

    it 'desfaz canal e caixa se o registro de delivery falhar' do
      stub_connected
      stub_request(:put, gateway_url("/connections/#{conn_id}/delivery")).to_return(status: 500, body: '{}')
      expect { post "#{base}/#{conn_id}/finalize", headers: admin.create_new_auth_token, params: finalize_params, as: :json }
        .not_to change(Inbox, :count)
      expect(response).to have_http_status(:bad_gateway)
      expect(Channel::InstagramUnofficial.count).to eq(0)
    end

    it 'cria canal do provedor certo (messenger)' do
      stub_connected(provider: 'messenger')
      stub_request(:put, gateway_url("/connections/#{conn_id}/delivery")).to_return(status: 200, body: '{}')
      stub_request(:post, gateway_url("/connections/#{conn_id}/sync")).to_return(status: 200, body: '{}')
      post "#{base}/#{conn_id}/finalize", headers: admin.create_new_auth_token, params: finalize_params, as: :json
      expect(Channel::MessengerUnofficial.where(connection_id: conn_id)).to exist
    end
  end
end
