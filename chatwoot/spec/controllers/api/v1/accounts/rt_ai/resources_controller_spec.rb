require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Resources', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
  end

  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo') { example.run }
  end

  it 'only serves allowlisted resources' do
    get "/api/v1/accounts/#{account.id}/rt_ai/resources/etc_passwd", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'lets an administrator list and create providers, forwarding only allowed fields' do
    allow(Rt::EngineClient).to receive(:get).and_return([])
    allow(Rt::EngineClient).to receive(:post).and_return('id' => 'x')
    get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers",
         params: { name: 'n', provider: 'openai', model: 'm', api_key: 'k', tenant_id: 'hack' }, headers: admin.create_new_auth_token, as: :json
    expect(Rt::EngineClient).to have_received(:post).with('/api/ai-services', hash_excluding('tenant_id'), anything)
  end

  it 'no longer serves knowledge or credential resources (credentials has its own endpoint)' do
    %w[credentials sources files memories payments].each do |key|
      get "/api/v1/accounts/#{account.id}/rt_ai/resources/#{key}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found), key
    end
  end

  it 'denies operators provider management' do
    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers", params: { name: 'x' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
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

  it 'shows client-friendly model names in usage' do
    allow(Rt::EngineClient).to receive(:get).and_return(
      'totals' => { 'calls' => 1 },
      'by_model' => [{ 'provider' => 'ninerouter', 'model' => 'ninerouter-gpt', 'calls' => 1, 'tokens' => 3, 'cost_usd' => 0.1 }]
    )
    get "/api/v1/accounts/#{account.id}/rt_ai/resources/usage", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.body.downcase).not_to include('ninerouter')
    expect(response.parsed_body['by_model'].first['model']).to eq('GPT')
  end

  it 'renames product names in integration keys without changing the engine data' do
    allow(Rt::EngineClient).to receive(:get).and_return([{ 'id' => 'k1', 'name' => 'Bridge Chatwoot (regravado 21/08)', 'is_active' => true }])
    get "/api/v1/accounts/#{account.id}/rt_ai/resources/integrations", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.first['name']).to eq('Canal de mensagens (regravado 21/08)')
  end

  it 'lists runs from the engine runs route, forwarding only integer paging' do
    allow(Rt::EngineClient).to receive(:get).and_return('items' => [], 'total' => 0, 'page' => 2, 'per_page' => 10)
    get "/api/v1/accounts/#{account.id}/rt_ai/resources/runs", params: { page: '2', per_page: '10', evil: 'x' },
                                                               headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::EngineClient).to have_received(:get).with('/api/runs?page=2&per_page=10', anything)
  end
end
