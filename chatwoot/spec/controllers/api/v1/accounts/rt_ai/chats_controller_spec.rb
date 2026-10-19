require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Chats', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
  end

  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo') { example.run }
  end

  it 'blocks when AI is not enabled for the account' do
    Rt::AiAccount.update_all(flags: {}) # rubocop:disable Rails/SkipsModelValidations
    get "/api/v1/accounts/#{account.id}/rt_ai/chats", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['code']).to eq('ai_unavailable')
  end

  it 'lists chats through the engine with a signed context' do
    allow(Rt::EngineClient).to receive(:get).and_return([{ 'id' => 'a' }])
    get "/api/v1/accounts/#{account.id}/rt_ai/chats", headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::EngineClient).to have_received(:get).with('/api/chats', claims: hash_including(aud: 'ui', account_id: account.id))
  end

  it 'filters templates: only published and never the system factory' do
    allow(Rt::EngineClient).to receive(:get).and_return(
      [{ 'id' => '1', 'active_version_id' => 'v' }, { 'id' => '2' }, { 'id' => '3', 'active_version_id' => 'v', 'system_key' => 'template_factory' }]
    )
    get "/api/v1/accounts/#{account.id}/rt_ai/chats/templates", headers: headers, as: :json
    expect(response.parsed_body.pluck('id')).to eq(['1'])
  end

  it 'rejects ids that are not UUIDs and issues a short-lived ticket' do
    get "/api/v1/accounts/#{account.id}/rt_ai/chats/not-a-uuid/messages", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "/api/v1/accounts/#{account.id}/rt_ai/chats/stream_ticket", headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['expires_in']).to be <= 60
  end

  it 'denies a reader without ai.chat.run the stream ticket' do
    reader = create(:user, account: account, role: :agent)
    Rt::AiGrant.create!(account_user: reader.account_users.find_by(account: account), role_key: 'leitor')
    post "/api/v1/accounts/#{account.id}/rt_ai/chats/stream_ticket", headers: reader.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
