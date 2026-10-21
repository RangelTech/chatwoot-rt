require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Resources', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
  end

  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo',
                      GATEWAY_BASE_URL: 'http://gateway.test', GATEWAY_ADMIN_TOKEN: 'segredo') { example.run }
  end

  it 'only serves allowlisted resources' do
    get "/api/v1/accounts/#{account.id}/rt_ai/resources/etc_passwd", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'lets an administrator list and create providers, forwarding only allowed fields' do
    allow(Rt::GatewayClient).to receive(:get).and_return('connections' => [])
    allow(Rt::GatewayClient).to receive(:post).and_return('connection' => { 'id' => 'x' })
    get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers",
         params: { name: 'n', provider: 'openai', model: 'm', api_key: 'k', tenant_id: 'hack' }, headers: admin.create_new_auth_token, as: :json
    expect(Rt::GatewayClient).to have_received(:post).with(
      account: account, path: '/api/providers', payload: hash_excluding(:tenant_id)
    )
  end

  it 'no longer serves knowledge or credential resources (credentials has its own endpoint)' do
    %w[credentials sources files memories payments].each do |key|
      get "/api/v1/accounts/#{account.id}/rt_ai/resources/#{key}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found), key
    end
  end

  it 'reads the tenant quota summary through the Gateway BFF' do
    tenant_id = Rt::AiAccount.find_by!(account_id: account.id).engine_tenant_id
    allow(Rt::GatewayClient).to receive(:get).and_return('rpm' => 60, 'requests' => 0)

    get "/api/v1/accounts/#{account.id}/rt_ai/resources/quotas", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('rpm' => 60)
    expect(Rt::GatewayClient).to have_received(:get).with(
      account: account, path: "/api/tenants/#{tenant_id}/summary"
    )
  end

  it 'lists only the logged-in tenant request log through the Gateway BFF' do
    tenant_id = Rt::AiAccount.find_by!(account_id: account.id).engine_tenant_id
    allow(Rt::GatewayClient).to receive(:get).and_return('requests' => [])

    get "/api/v1/accounts/#{account.id}/rt_ai/resources/requests", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(Rt::GatewayClient).to have_received(:get).with(
      account: account, path: "/api/tenants/#{tenant_id}/requests?limit=50"
    )
  end

  it 'denies operators provider management' do
    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers", params: { name: 'x' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'tests a provider only through the tenant-scoped gateway BFF route' do
    provider_id = SecureRandom.uuid
    allow(Rt::GatewayClient).to receive(:post).and_return('valid' => true, 'refreshed' => false)

    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/#{provider_id}/actions/test",
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('valid' => true)
    expect(Rt::GatewayClient).to have_received(:post).with(
      account: account, path: "/api/providers/#{provider_id}/test"
    )
  end

  it 'lists provider models only through the tenant-scoped gateway BFF route' do
    provider_id = SecureRandom.uuid
    allow(Rt::GatewayClient).to receive(:get).and_return('models' => [{ 'id' => 'model-a', 'name' => 'Model A' }])

    get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/#{provider_id}/models",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('models' => include('id' => 'model-a'))
    expect(Rt::GatewayClient).to have_received(:get).with(
      account: account, path: "/api/providers/#{provider_id}/models"
    )
  end

  it 'lists a provider active state and changes it only through the tenant-scoped BFF' do
    provider_id = SecureRandom.uuid
    allow(Rt::GatewayClient).to receive(:get).and_return('connections' => [{ 'id' => provider_id, 'isActive' => true }])
    allow(Rt::GatewayClient).to receive(:put).and_return('id' => provider_id, 'isActive' => false)

    get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include(include('id' => provider_id, 'is_active' => true))

    put "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/#{provider_id}",
        params: { is_active: false, tenant_id: 'browser-must-not-control-this' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(Rt::GatewayClient).to have_received(:put).with(
      account: account, path: "/api/providers/#{provider_id}", payload: { isActive: false }
    )
  end

  it 'restricts environment actions to the allowlist and to environment managers' do
    allow(Rt::EngineClient).to receive(:post).and_return('ok' => true)
    post "/api/v1/accounts/#{account.id}/rt_ai/resources/environment/actions/start", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    post "/api/v1/accounts/#{account.id}/rt_ai/resources/environment/actions/rm_rf", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    post "/api/v1/accounts/#{account.id}/rt_ai/resources/environment/actions/start", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'forwards show_progress (progress message permission) to the engine and drops unknown fields' do
    allow(Rt::EngineClient).to receive(:put).and_return('ok' => true)
    put "/api/v1/accounts/#{account.id}/rt_ai/resources/inboxes/12",
        params: { template_id: SecureRandom.uuid, autopilot: true, show_progress: true, admin: true },
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::EngineClient).to have_received(:put).with(
      '/api/omnichannel/inboxes/12/ia',
      hash_including('show_progress' => true, 'autopilot' => true),
      anything
    )
    expect(Rt::EngineClient).not_to have_received(:put).with(anything, hash_including('admin' => true), anything)
  end

  it 'updates an inbox agent link through the inbox routing endpoint' do
    allow(Rt::EngineClient).to receive(:put).and_return('ok' => true)
    put "/api/v1/accounts/#{account.id}/rt_ai/resources/inboxes/12", params: { template_id: SecureRandom.uuid, autopilot: true },
                                                                    headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::EngineClient).to have_received(:put).with('/api/omnichannel/inboxes/12/ia', anything, anything)
  end
end
