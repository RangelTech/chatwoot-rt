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

  it 'forwards feedback with the rated message id and an integer rating' do
    chat_id = SecureRandom.uuid
    allow(Rt::EngineClient).to receive(:post).and_return({ 'status' => 'ok' })
    post "/api/v1/accounts/#{account.id}/rt_ai/chats/#{chat_id}/feedback",
         params: { message_id: 'm-1', rating: '1', comment: 'ótimo' }, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::EngineClient).to have_received(:post)
      .with("/api/chats/#{chat_id}/feedback", { 'message_id' => 'm-1', 'comment' => 'ótimo', 'rating' => 1 }, claims: anything)
  end

  it 'denies the reader feedback (needs ai.chat.run)' do
    reader = create(:user, account: account, role: :agent)
    Rt::AiGrant.create!(account_user: reader.account_users.find_by(account: account), role_key: 'leitor')
    post "/api/v1/accounts/#{account.id}/rt_ai/chats/#{SecureRandom.uuid}/feedback",
         params: { message_id: 'm', rating: 1 }, headers: reader.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  context 'with artifacts' do
    let(:chat_id) { SecureRandom.uuid }
    let(:artifact_id) { SecureRandom.uuid }
    let(:listing) { [{ 'artifact_id' => artifact_id, 'kind' => 'file', 'title' => '../relatorio.xlsx', 'row_count' => nil }] }
    let(:base) { "/api/v1/accounts/#{account.id}/rt_ai/chats/#{chat_id}/artifacts" }

    it 'lists the chat artifacts with an id alias' do
      allow(Rt::EngineClient).to receive(:get).and_return(listing)
      get base, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['id']).to eq(artifact_id)
    end

    it 'returns 404 when the engine says the chat is not the user\'s' do
      allow(Rt::EngineClient).to receive(:get).and_raise(Rt::EngineClient::Error.new('404', status: 404))
      get base, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'proxies the download as an attachment with a sanitized name' do
      allow(Rt::EngineClient).to receive(:get).and_return(listing)
      allow(Rt::EngineClient).to receive(:download).and_return({ body: 'abc', content_type: 'application/pdf' })
      get "#{base}/#{artifact_id}/download", headers: headers
      expect(response).to have_http_status(:success)
      expect(response.body).to eq('abc')
      expect(response.headers['Content-Disposition']).to include('attachment').and include('relatorio.xlsx')
      expect(response.headers['Content-Disposition']).not_to include('..')
      expect(Rt::EngineClient).to have_received(:download).with("/api/artifacts/#{artifact_id}/download", claims: anything)
    end

    it 'only serves images inline' do
      allow(Rt::EngineClient).to receive(:get).and_return(listing)
      allow(Rt::EngineClient).to receive(:download).and_return({ body: 'x', content_type: 'text/html' })
      get "#{base}/#{artifact_id}/download", params: { inline: 1 }, headers: headers
      expect(response.headers['Content-Disposition']).to include('attachment')
      allow(Rt::EngineClient).to receive(:download).and_return({ body: 'x', content_type: 'image/png' })
      get "#{base}/#{artifact_id}/download", params: { inline: 1 }, headers: headers
      expect(response.headers['Content-Disposition']).to include('inline')
    end

    it 'does not download an artifact that is not in the user\'s chat' do
      allow(Rt::EngineClient).to receive(:get).and_return(listing)
      allow(Rt::EngineClient).to receive(:download)
      get "#{base}/#{SecureRandom.uuid}/download", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(Rt::EngineClient).not_to have_received(:download)
    end

    it 'rejects non-UUID ids' do
      get "#{base}/xyz/download", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
