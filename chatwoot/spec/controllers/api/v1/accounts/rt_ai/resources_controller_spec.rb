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

  it 'serves the generated public provider catalog without calling the gateway' do
    allow(Rt::GatewayClient).to receive(:get)

    get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/catalog", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('source')).to eq('9router')
    expect(response.parsed_body.fetch('providers')).to include(include('id' => 'openai'))
    expect(Rt::GatewayClient).not_to have_received(:get)
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

  it 'tests a provider group only through the tenant-scoped gateway batch route' do
    allow(Rt::GatewayClient).to receive(:post).and_return('summary' => { 'total' => 2, 'passed' => 2, 'failed' => 0 })

    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/test-batch",
         params: { mode: 'provider', provider_id: 'openai' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(Rt::GatewayClient).to have_received(:post).with(
      account: account, path: '/api/providers/test-batch', payload: { mode: 'provider', providerId: 'openai' }
    )
  end

  it 'validates a provider key only through the tenant-scoped gateway BFF route' do
    allow(Rt::GatewayClient).to receive(:post).and_return('valid' => true)

    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/validate",
         params: { provider: 'openai', api_key: 'test-key', tenant_id: 'browser-must-not-control-this' },
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('valid' => true)
    expect(Rt::GatewayClient).to have_received(:post).with(
      account: account, path: '/api/providers/validate', payload: { provider: 'openai', apiKey: 'test-key' }
    )
  end

  it 'rejects an invalid provider validation request before it reaches the gateway' do
    allow(Rt::GatewayClient).to receive(:post)

    post "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/validate",
         params: { provider: '../openai', api_key: 'test-key' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Rt::GatewayClient).not_to have_received(:post)
  end

  it 'lists provider models only through the tenant-scoped gateway BFF route' do
    provider_id = SecureRandom.uuid
    allow(Rt::GatewayClient).to receive(:get).and_return('models' => [{ 'id' => 'model-a', 'name' => 'Model A' }])

    get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/#{provider_id}/models",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('models')).to include(include('id' => 'model-a'))
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
  describe 'combos (G-4)' do
    let(:url) { "/api/v1/accounts/#{account.id}/rt_ai/resources/combos" }

    it 'forwards name, ordered models and strategy only, never a tenant from the browser' do
      allow(Rt::GatewayClient).to receive(:post).and_return('id' => 'c')
      post url, params: { name: 'principal', models: %w[a/m1 b/m2], strategy: { fallbackStrategy: 'round-robin', evil: 1 }, tenantId: 'outro', tenant_id: 'outro' },
                headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::GatewayClient).to have_received(:post).with(
        account: account, path: '/api/combos',
        payload: { name: 'principal', models: %w[a/m1 b/m2], strategy: { 'fallbackStrategy' => 'round-robin' } }
      )
    end

    it 'rejects malformed names, models and strategies before reaching the gateway' do
      allow(Rt::GatewayClient).to receive(:post)
      [{ name: '../x', models: [] }, { name: 'ok', models: ['a;rm -rf'] }, { name: 'ok', models: %w[a/m], strategy: { fallbackStrategy: 'x' } },
       { name: 'ok', models: (1..31).map { |i| "a/m#{i}" } }].each do |body|
        post url, params: body, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity), body.inspect
      end
      expect(Rt::GatewayClient).not_to have_received(:post)
    end

    it 'passes a gateway refusal for a foreign provider (400) through as a business error' do
      allow(Rt::GatewayClient).to receive(:post).and_raise(Rt::GatewayClient::Error.new('400', status: 400, body: {}))
      post url, params: { name: 'x', models: %w[de-outro/m] }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it 'translates the gateway refusal for a provider the company does not have' do
      body = { 'error' => 'provider of "anthropic/x" is not configured in this tenant' }
      error = Rt::GatewayClient::Error.new('400', status: 400, body: body)
      allow(Rt::GatewayClient).to receive(:post).and_raise(error)
      post url, params: { name: 'x', models: %w[anthropic/x] }, headers: admin.create_new_auth_token, as: :json
      message = response.parsed_body['message']
      expect(message).to eq('O provedor do modelo "anthropic/x" não está configurado nesta empresa.')
      expect(message).not_to match(/tenant/i)
    end

    it 'updates only the sent combo fields and denies it to readers' do
      allow(Rt::GatewayClient).to receive(:put).and_return('id' => 'c')
      id = SecureRandom.uuid
      put "#{url}/#{id}", params: { name: 'novo' }, headers: admin.create_new_auth_token, as: :json
      expect(Rt::GatewayClient).to have_received(:put).with(account: account, path: "/api/combos/#{id}", payload: { name: 'novo' })
      put "#{url}/#{id}", params: { name: 'novo' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'tenant isolation (GW adversarial, BFF layer)' do
    it 'always sends the tenant of the session Account, ignoring ids in params, headers and ids of other accounts' do
      other = create(:account)
      Rt::AiAccount.create!(account: other, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
      allow(Rt::GatewayClient).to receive(:get).and_return('connections' => [])

      get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers?tenantId=#{other.id}&tenant_id=#{other.id}",
          headers: admin.create_new_auth_token.merge('X-Tenant-Id' => 'outro'), as: :json

      expect(Rt::GatewayClient).to have_received(:get).with(account: account, path: '/api/providers')
      expect(Rt::GatewayClient).not_to have_received(:get).with(account: other, path: anything)
    end

    it 'denies an administrator of one account from reaching another account resources' do
      other = create(:account)
      Rt::AiAccount.create!(account: other, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
      allow(Rt::GatewayClient).to receive(:get)
      get "/api/v1/accounts/#{other.id}/rt_ai/resources/providers", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      expect(Rt::GatewayClient).not_to have_received(:get)
    end

    it 'validates ids: provider routes never forward free-form paths' do
      allow(Rt::GatewayClient).to receive(:delete)
      delete "/api/v1/accounts/#{account.id}/rt_ai/resources/providers/not-an-id", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(Rt::GatewayClient).not_to have_received(:delete)
    end

    it 'returns an unavailable-gateway error without leaking the admin token or tenant' do
      allow(Rt::GatewayClient).to receive(:get).and_raise(Rt::GatewayClient::Error.new('boom segredo', status: 500))
      get "/api/v1/accounts/#{account.id}/rt_ai/resources/providers", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:bad_gateway)
      expect(response.body).not_to include('segredo')
    end
  end

  describe 'permission matrix ai.providers.* (Leitor/Operador/Gestor/Admin)' do
    it 'grants view/manage exactly as the spec table' do
      expected = { 'leitor' => [false, false], 'operador' => [false, false], 'gestor' => [true, false], 'administrador_ia' => [true, true] }
      expected.each do |role, (view, manage)|
        perms = Rt::AiRoles.permissions_for(role)
        expect(perms.include?('ai.providers.view')).to eq(view), role
        expect(perms.include?('ai.providers.manage')).to eq(manage), role
      end
    end
  end

  describe 'runs (Execuções)' do
    let(:url) { "/api/v1/accounts/#{account.id}/rt_ai/resources/runs" }

    it 'reads the tenant runs route and forwards only numeric page and per_page' do
      allow(Rt::EngineClient).to receive(:get).and_return('items' => [], 'total' => 0)
      get "#{url}?page=3&per_page=500&tenant_id=hack", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:get).with('/api/runs?page=3&per_page=100', claims: anything)
    end

    it 'defaults to the first page of 25 and clamps garbage' do
      allow(Rt::EngineClient).to receive(:get).and_return('items' => [], 'total' => 0)
      get "#{url}?page=abc", headers: admin.create_new_auth_token, as: :json
      expect(Rt::EngineClient).to have_received(:get).with('/api/runs?page=1&per_page=25', claims: anything)
    end
  end

  describe 'environment services (AMB-2)' do
    let(:base) { "/api/v1/accounts/#{account.id}/rt_ai/resources/environment_services" }
    let(:payload) { { 'ambiente' => 'ativo', 'servicos' => [{ 'nome' => 'web', 'estado' => 'rodando' }], 'soltos' => [] } }

    it 'lists through the engine without ever forwarding a tenant from the browser' do
      allow(Rt::EngineClient).to receive(:get).and_return(payload)
      get "#{base}?tenant_id=hack&account_id=999", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['servicos'].first['nome']).to eq('web')
      expect(Rt::EngineClient).to have_received(:get).with('/api/environment/services', claims: anything)
    end

    it 'reports a stopped environment as data, not as an error' do
      allow(Rt::EngineClient).to receive(:get).and_return('ambiente' => 'parado', 'servicos' => [], 'soltos' => [])
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ambiente']).to eq('parado')
    end

    it 'denies listing to users without ai.environment.view' do
      allow(Rt::EngineClient).to receive(:get)
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Rt::EngineClient).not_to have_received(:get)
    end

    it 'lets managers act and read logs, only with allowlisted names and actions' do
      allow(Rt::EngineClient).to receive(:post).and_return('ok' => true)
      allow(Rt::EngineClient).to receive(:get).and_return('log' => 'x')
      post "#{base}/web/actions/stop", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:post).with('/api/environment/services/web/stop', {}, anything)
      get "#{base}/web/logs", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      post "#{base}/web/actions/rm_rf", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      post "#{base}/Web%3Bx/actions/stop", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      get "#{base}/..%2Fetc/logs", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'denies actions and logs to operators' do
      allow(Rt::EngineClient).to receive(:post)
      allow(Rt::EngineClient).to receive(:get)
      post "#{base}/web/actions/stop", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      get "#{base}/web/logs", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Rt::EngineClient).not_to have_received(:post)
    end

    it 'does not serve another account to a member of this one' do
      other = create(:account)
      Rt::AiAccount.create!(account: other, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
      allow(Rt::EngineClient).to receive(:get).and_return(payload)
      get "/api/v1/accounts/#{other.id}/rt_ai/resources/environment_services", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden).or have_http_status(:not_found)
      expect(Rt::EngineClient).not_to have_received(:get)
    end
  end
end
