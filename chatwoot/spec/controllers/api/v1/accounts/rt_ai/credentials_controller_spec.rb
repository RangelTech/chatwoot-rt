require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Credentials', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/rt_ai/credentials" }
  let(:secret_row) do
    { 'id' => SecureRandom.uuid, 'name' => 'SSH_DO_SERVIDOR', 'kind' => 'ssh', 'hint' => nil,
      'meta' => { 'host' => '10.0.0.1', 'port' => 22, 'user' => 'root' },
      'env_vars' => %w[SSH_DO_SERVIDOR SSH_DO_SERVIDOR_HOST SSH_DO_SERVIDOR_PORT SSH_DO_SERVIDOR_USER],
      'is_active' => true, 'created_at' => '2026-10-20T10:00:00Z', 'updated_at' => '2026-10-20T10:00:00Z',
      'value_encrypted' => 'NAO-PODE-VAZAR', 'private_key' => 'NAO-PODE-VAZAR' }
  end

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
  end

  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo') { example.run }
  end

  def stub_lists(overrides = {})
    allow(Rt::EngineClient).to receive(:get) do |path, **|
      overrides.fetch(path) { path == '/api/secrets' ? [secret_row] : [] }
    end
  end

  describe 'GET index' do
    it 'merges every credential source into one list without any value' do
      stub_lists(
        '/api/datasources' => [{ 'id' => SecureRandom.uuid, 'name' => 'loja', 'kind' => 'postgresql', 'has_secret' => true,
                                 'config' => { 'host' => 'db', 'port' => 5432, 'database' => 'loja', 'user' => 'app' },
                                 'env_vars' => ['DB_LOJA_URL'], 'secret_encrypted' => 'NAO-PODE-VAZAR' }],
        '/api/payments/credentials' => [{ 'id' => SecureRandom.uuid, 'sandbox' => true, 'has_token' => true,
                                          'access_token_encrypted' => 'NAO-PODE-VAZAR', 'env_vars' => ['MERCADO_PAGO_TOKEN'] }],
        '/api/google-accounts' => [{ 'id' => SecureRandom.uuid, 'label' => 'Agenda', 'email_address' => 'a@x.com',
                                     'env_vars' => ['GOOGLE_AGENDA_TOKEN'] }]
      )
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      items = response.parsed_body['items']
      expect(items.pluck('type')).to match_array(%w[database google payment ssh])
      ssh = items.find { |i| i['type'] == 'ssh' }
      expect(ssh['name']).to eq('SSH_DO_SERVIDOR')
      expect(ssh['info']).to include('host' => '10.0.0.1', 'user' => 'root')
      expect(ssh['env_vars']).to include('SSH_DO_SERVIDOR_HOST')
      db = items.find { |i| i['type'] == 'database' }
      expect(db['info']).to include('db_kind' => 'postgres', 'host' => 'db', 'has_password' => true)
      expect(response.body).not_to include('NAO-PODE-VAZAR')
    end

    it 'keeps working when one source fails and fails only when all do' do
      allow(Rt::EngineClient).to receive(:get) do |path, **|
        raise Rt::EngineClient::Error.new('boom', status: 500) if path == '/api/datasources'

        []
      end
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      allow(Rt::EngineClient).to receive(:get).and_raise(Rt::EngineClient::Error.new('boom', status: 500))
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_gateway)
    end

    it 'denies users without ai.credentials.view' do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST create' do
    before { allow(Rt::EngineClient).to receive(:post).and_return('id' => 'x') }

    it 'stores an SSH credential as a named secret with host, port and user as metadata' do
      params = { type: 'ssh', name: 'do servidor', value: '-----BEGIN KEY-----', host: '10.0.0.1', port: 22, user: 'root', tenant_id: 'hack' }
      post base, params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:post).with(
        '/api/secrets',
        { 'name' => 'do servidor', 'value' => '-----BEGIN KEY-----', 'kind' => 'ssh',
          'meta' => { 'host' => '10.0.0.1', 'port' => 22, 'user' => 'root' } },
        anything
      )
    end

    it 'stores a GCP service account as a gcp secret' do
      post base, params: { type: 'gcp', name: 'SA', value: '{"client_email":"a"}' }, headers: admin.create_new_auth_token, as: :json
      expect(Rt::EngineClient).to have_received(:post).with('/api/secrets', hash_including('kind' => 'gcp', 'name' => 'SA'), anything)
    end

    it 'turns a database into a datasource, keeping the password out of the config' do
      post base, params: { type: 'database', db_kind: 'mongo', name: 'clientes', host: 'm', port: '27017', user: 'app', password: 'p', ssl: true },
                 headers: admin.create_new_auth_token, as: :json
      expect(Rt::EngineClient).to have_received(:post).with(
        '/api/datasources',
        { 'name' => 'clientes', 'kind' => 'mongodb', 'config' => { 'host' => 'm', 'user' => 'app', 'port' => 27_017, 'ssl' => true },
          'secret' => 'p' },
        anything
      )
    end

    it 'rejects an unknown database type and an unknown credential type' do
      post base, params: { type: 'database', db_kind: 'oracle9', name: 'x' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post base, params: { type: 'etc_passwd', name: 'x' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'does not create connected accounts by form (they use OAuth)' do
      post base, params: { type: 'google', name: 'x' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'uses the single company payment credential endpoint' do
      allow(Rt::EngineClient).to receive(:put).and_return('id' => 'p')
      post base, params: { type: 'payment', access_token: 'APP_USR-1', sandbox: false }, headers: admin.create_new_auth_token, as: :json
      expect(Rt::EngineClient).to have_received(:put).with('/api/payments/credentials', { 'access_token' => 'APP_USR-1', 'sandbox' => false },
                                                           anything)
    end

    it 'denies users without ai.credentials.manage' do
      post base, params: { type: 'secret', name: 'x', value: 'y' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Rt::EngineClient).not_to have_received(:post)
    end
  end

  describe 'PUT update and DELETE destroy' do
    let(:id) { SecureRandom.uuid }

    it 'replaces only the value of a secret' do
      allow(Rt::EngineClient).to receive(:put).and_return('id' => id)
      put "#{base}/secret/#{id}", params: { type: 'secret', value: 'novo', name: 'OUTRO' }, headers: admin.create_new_auth_token, as: :json
      expect(Rt::EngineClient).to have_received(:put).with("/api/secrets/#{id}", { 'value' => 'novo' }, anything)
    end

    it 'keeps the current password when replacing a database with a blank one' do
      allow(Rt::EngineClient).to receive(:put).and_return('id' => id)
      put "#{base}/database/#{id}", params: { host: 'novo', password: '' }, headers: admin.create_new_auth_token, as: :json
      expect(Rt::EngineClient).to have_received(:put).with("/api/datasources/#{id}", { 'config' => { 'host' => 'novo' } }, anything)
    end

    it 'can turn SSL off when replacing a database (false is not the same as blank)' do
      allow(Rt::EngineClient).to receive(:put).and_return('id' => id)
      put "#{base}/database/#{id}", params: { host: 'h', ssl: false }, headers: admin.create_new_auth_token, as: :json
      expect(Rt::EngineClient).to have_received(:put).with("/api/datasources/#{id}", { 'config' => { 'host' => 'h', 'ssl' => false } }, anything)
    end

    it 'removes through the allowlisted path, tolerating empty engine responses' do
      allow(Rt::EngineClient).to receive(:delete).and_raise(JSON::ParserError)
      delete "#{base}/email/#{id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:delete).with("/api/email-accounts/#{id}", anything)
    end

    it 'rejects bad ids, unknown types and unprivileged users' do
      delete "#{base}/secret/not-a-uuid", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      delete "#{base}/users/#{id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      delete "#{base}/secret/#{id}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST oauth_start' do
    it 'returns only the authorization url' do
      allow(Rt::EngineClient).to receive(:post).and_return('auth_url' => 'https://accounts.google.com/x', 'state' => 'segredo-de-estado')
      post "#{base}/oauth/google", params: { label: 'Agenda' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('auth_url' => 'https://accounts.google.com/x')
      expect(Rt::EngineClient).to have_received(:post).with('/api/credentials/oauth/google/iniciar', { label: 'Agenda' }, anything)
    end

    it 'only accepts google and microsoft and requires manage permission' do
      post "#{base}/oauth/dropbox", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      post "#{base}/oauth/microsoft", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'passes the engine explanation when the provider is not configured' do
      detail = { 'detail' => 'A conexão com este serviço ainda não foi configurada' }
      allow(Rt::EngineClient).to receive(:post).and_raise(Rt::EngineClient::Error.new('x', status: 422, body: detail))
      post "#{base}/oauth/microsoft", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
