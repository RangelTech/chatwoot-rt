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

  describe 'company skills' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:base) { "/api/v1/accounts/#{account.id}/rt_ai" }

    it 'lets an operator read them but not write' do
      allow(Rt::EngineClient).to receive(:get).and_return([])
      get "#{base}/skills/company", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:get).with('/api/skills/company', anything)
      post "#{base}/skills/company", params: { content: '---' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      put "#{base}/skills/company/#{SecureRandom.uuid}", params: { content: '---' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{base}/skills/company/#{SecureRandom.uuid}", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/skills/company/#{SecureRandom.uuid}/act/disable", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'lets an administrator create, edit, toggle and delete through the engine' do
      id = SecureRandom.uuid
      allow(Rt::EngineClient).to receive_messages(post: { 'id' => id }, put: { 'id' => id }, delete: { 'status' => 'ok' })
      post "#{base}/skills/company", params: { content: 'skill-md' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:post).with('/api/skills/company', { content: 'skill-md' }, anything)
      put "#{base}/skills/company/#{id}", params: { content: 'x' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      post "#{base}/skills/company/#{id}/act/disable", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      post "#{base}/skills/company/#{id}/act/explode", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      delete "#{base}/skills/company/#{id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'passes engine validation problems to the user' do
      error = Rt::EngineClient::Error.new('422', status: 422, body: { 'detail' => 'x', 'problems' => [{ 'message' => 'Falta o campo description' }] })
      allow(Rt::EngineClient).to receive(:post).and_raise(error)
      post "#{base}/skills/company", params: { content: 'x' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('Falta o campo description')
    end

    it 'keeps 502 for engine outages' do
      allow(Rt::EngineClient).to receive(:get).and_raise(Rt::EngineClient::Error.new('500', status: 500))
      get "#{base}/skills/company", headers: headers, as: :json
      expect(response).to have_http_status(:bad_gateway)
    end
  end

  describe 'own skills' do
    let(:base) { "/api/v1/accounts/#{account.id}/rt_ai" }

    it 'creates, reads and edits through the engine, sending only the content' do
      id = SecureRandom.uuid
      allow(Rt::EngineClient).to receive_messages(get: { 'id' => id }, post: { 'id' => id }, put: { 'id' => id })
      post "#{base}/skills", params: { content: 'abc', tenant_id: 'x' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:post).with('/api/me/skills', { content: 'abc' }, anything)
      get "#{base}/skills/#{id}", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      put "#{base}/skills/#{id}", params: { content: 'def' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      get "#{base}/skills/nao-uuid", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'routines' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:base) { "/api/v1/accounts/#{account.id}/rt_ai" }

    it 'creates with a friendly frequency, filtering unknown params' do
      allow(Rt::EngineClient).to receive(:post).and_return('id' => 'r')
      body = { name: 'Resumo', instruction: 'Resuma', template_id: SecureRandom.uuid, timezone: 'America/Sao_Paulo',
               frequency: { kind: 'weekly', time: '08:00', weekdays: [1, 3] }, tenant_id: 'outro', user_id: 'outro' }
      post "#{base}/routines", params: body, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:post) do |path, payload, _|
        expect(path).to eq('/api/schedules')
        expect(payload.keys).not_to include('tenant_id', 'user_id')
        expect(payload['frequency']).to include('kind' => 'weekly', 'weekdays' => [1, 3])
      end
    end

    it 'updates, lists the run history and denies operators the write routes' do
      id = SecureRandom.uuid
      allow(Rt::EngineClient).to receive_messages(put: { 'id' => id }, get: { 'runs' => [] })
      put "#{base}/routines/#{id}", params: { name: 'Novo', active: false }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      get "#{base}/routines/#{id}/runs", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:get).with("/api/schedules/#{id}/runs", anything)
      post "#{base}/routines", params: { name: 'x' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      put "#{base}/routines/#{id}", params: { name: 'x' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
