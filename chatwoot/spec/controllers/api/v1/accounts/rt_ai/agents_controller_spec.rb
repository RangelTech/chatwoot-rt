require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Agents', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
  end

  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo') { example.run }
  end

  it 'lets an operator list agents but not create or publish' do
    allow(Rt::EngineClient).to receive(:get).and_return([])
    get "/api/v1/accounts/#{account.id}/rt_ai/agents", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    post "/api/v1/accounts/#{account.id}/rt_ai/agents", params: { name: 'x' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    id = SecureRandom.uuid
    post "/api/v1/accounts/#{account.id}/rt_ai/agents/#{id}/publish", params: { version_id: id }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'lets an administrator create (defaulting to skills) and validate a draft through the engine' do
    allow(Rt::EngineClient).to receive(:post).and_return('id' => 'novo')
    post "/api/v1/accounts/#{account.id}/rt_ai/agents", params: { name: 'Vendas' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::EngineClient).to have_received(:post).with('/api/templates', hash_including('agent_kind' => 'skills'), anything)
    id = SecureRandom.uuid
    post "/api/v1/accounts/#{account.id}/rt_ai/agents/#{id}/validate",
         params: { files: [{ path: 'AGENTE.md', content: '# a' }], manifest: { tools: [] } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'rejects ids that are not UUIDs' do
    get "/api/v1/accounts/#{account.id}/rt_ai/agents/abc/draft", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
