require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Skills', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
  end

  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo') { example.run }
  end

  it 'lists the user skills and routines for an operator' do
    allow(Rt::EngineClient).to receive(:get).and_return([])
    get "/api/v1/accounts/#{account.id}/rt_ai/skills", headers: headers, as: :json
    expect(response).to have_http_status(:success)
    get "/api/v1/accounts/#{account.id}/rt_ai/skills/routines", headers: headers, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'approves an own skill and only allows known actions' do
    allow(Rt::EngineClient).to receive(:post).and_return('ok' => true)
    id = SecureRandom.uuid
    post "/api/v1/accounts/#{account.id}/rt_ai/skills/#{id}/act/approve", headers: headers, as: :json
    expect(response).to have_http_status(:success)
    post "/api/v1/accounts/#{account.id}/rt_ai/skills/#{id}/act/explode", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'denies memory review to operators' do
    get "/api/v1/accounts/#{account.id}/rt_ai/skills/memory_proposals", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
