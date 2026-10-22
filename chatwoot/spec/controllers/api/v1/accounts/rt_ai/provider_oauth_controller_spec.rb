require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::ProviderOauth', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/rt_ai" }

  before do
    [account, other_account].each do |acc|
      Rt::AiAccount.create!(account: acc, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
    end
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  around do |example|
    with_modified_env(GATEWAY_BASE_URL: 'http://gateway.test', GATEWAY_ADMIN_TOKEN: 'segredo') { example.run }
  end

  it 'starts an authorization-code flow keeping PKCE server-side' do
    allow(Rt::GatewayClient).to receive(:get).and_return('authUrl' => 'https://idp.test/auth', 'state' => 'st1', 'codeVerifier' => 'verifier-secret')

    get "#{base}/providers_oauth/codex/start", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('auth_url' => 'https://idp.test/auth', 'flow' => 'authorization_code')
    expect(response.body).not_to include('verifier-secret')
    expect(Rt::GatewayClient).to have_received(:get).with(account: account, path: %r{\A/api/oauth/codex/authorize\?redirect_uri=})
  end

  it 'exchanges the pasted callback URL with the stored verifier and the tenant of the session' do
    allow(Rt::GatewayClient).to receive(:get).and_return('authUrl' => 'u', 'state' => 'st1', 'codeVerifier' => 'v1')
    allow(Rt::GatewayClient).to receive(:post).and_return('connection' => { 'id' => 'c1', 'provider' => 'codex' })
    get "#{base}/providers_oauth/codex/start", headers: admin.create_new_auth_token, as: :json
    handle = response.parsed_body['state']

    post "#{base}/providers_oauth/codex/finish", params: { state: handle, callback_url: 'http://localhost:8080/callback?code=abc&state=st1', tenant_id: 'x' },
                                                  headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(Rt::GatewayClient).to have_received(:post).with(
      account: account, path: '/api/oauth/codex/exchange',
      payload: hash_including(code: 'abc', codeVerifier: 'v1', state: 'st1')
    )
  end

  it 'rejects a state returned by the provider that does not match' do
    allow(Rt::GatewayClient).to receive(:get).and_return('authUrl' => 'u', 'state' => 'st1', 'codeVerifier' => 'v1')
    allow(Rt::GatewayClient).to receive(:post)
    get "#{base}/providers_oauth/codex/start", headers: admin.create_new_auth_token, as: :json

    post "#{base}/providers_oauth/codex/finish", params: { state: response.parsed_body['state'], callback_url: 'http://x/cb?code=abc&state=OUTRO' },
                                                  headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Rt::GatewayClient).not_to have_received(:post)
  end

  it 'does not let another tenant finish a flow started by this one (handle is bound to the Account)' do
    allow(Rt::GatewayClient).to receive(:get).and_return('authUrl' => 'u', 'state' => 'st1', 'codeVerifier' => 'v1')
    allow(Rt::GatewayClient).to receive(:post)
    get "#{base}/providers_oauth/codex/start", headers: admin.create_new_auth_token, as: :json
    handle = response.parsed_body['state']

    post "/api/v1/accounts/#{other_account.id}/rt_ai/providers_oauth/codex/finish",
         params: { state: handle, callback_url: 'http://x/cb?code=abc&state=st1' }, headers: other_admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Rt::GatewayClient).not_to have_received(:post)
  end

  it 'only accepts allowlisted providers' do
    get "#{base}/providers_oauth/evil/start", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "#{base}/providers_oauth/cursor/start", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'denies registration to users without ai.providers.manage' do
    get "#{base}/providers_oauth/codex/start", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'runs the device flow with the device code kept server-side' do
    allow(Rt::GatewayClient).to receive(:get).and_return('userCode' => 'ABCD-1234', 'verificationUri' => 'https://v.test', 'deviceCode' => 'dev-secret', 'interval' => 5)
    allow(Rt::GatewayClient).to receive(:post).and_return('success' => true, 'connection' => { 'id' => 'c2' })
    get "#{base}/providers_oauth/github/start", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('userCode' => 'ABCD-1234', 'flow' => 'device_code')
    expect(response.body).not_to include('dev-secret')

    post "#{base}/providers_oauth/github/poll", params: { state: response.parsed_body['state'] }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('success' => true)
    expect(Rt::GatewayClient).to have_received(:post).with(
      account: account, path: '/api/oauth/github/poll', payload: hash_including(deviceCode: 'dev-secret')
    )
  end

  it 'imports an access token only for allowlisted providers' do
    allow(Rt::GatewayClient).to receive(:post).and_return('connection' => { 'id' => 'c3' })
    post "#{base}/providers_oauth/codex/import", params: { access_token: 'tok' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    post "#{base}/providers_oauth/github/import", params: { access_token: 'tok' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'simulates the whole flow without a real account when the Account flag is on' do
    Rt::AiAccount.find_by!(account_id: account.id).update!(flags: { 'ai_enabled' => true, 'oauth_simulator' => true })
    allow(Rt::GatewayClient).to receive(:post).and_return('connection' => { 'id' => 'sim1', 'provider' => 'codex' })

    get "#{base}/providers_oauth/codex/start", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('flow' => 'simulator')
    post "#{base}/providers_oauth/codex/finish", params: { state: response.parsed_body['state'] }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('simulated' => true, 'id' => 'sim1')
    expect(Rt::GatewayClient).to have_received(:post).with(
      account: account, path: '/api/oauth/codex/import-token', payload: hash_including(:accessToken)
    )
  end

  it 'reads a provider quota through the tenant-scoped route, view permission only' do
    provider_id = SecureRandom.uuid
    allow(Rt::GatewayClient).to receive(:get).and_return('message' => 'Usage not available')

    get "#{base}/resources/providers/#{provider_id}/quota", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::GatewayClient).to have_received(:get).with(account: account, path: "/api/usage/#{provider_id}")

    get "#{base}/resources/providers/not-a-uuid/quota", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    get "#{base}/resources/providers/#{provider_id}/quota", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
