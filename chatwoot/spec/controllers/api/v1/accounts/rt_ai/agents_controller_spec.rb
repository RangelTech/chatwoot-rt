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

  describe 'arquivos do pacote' do
    let(:id) { SecureRandom.uuid }
    let(:base) { "/api/v1/accounts/#{account.id}/rt_ai/agents/#{id}" }
    let(:pdf) { "%PDF-1.7\n".b + [0xE2, 0xE3, 0xCF, 0xD3].pack("C*") }

    def upload(name, data, user: admin, path: nil)
      file = Rack::Test::UploadedFile.new(StringIO.new(data), 'application/octet-stream', original_filename: name)
      params = { file: file }
      params[:path] = path if path
      post "#{base}/upload_file", params: params, headers: user.create_new_auth_token
    end

    it 'sends the bytes to the engine as base64 under arquivos/' do
      allow(Rt::EngineClient).to receive(:put).and_return('path' => 'arquivos/cardapio.pdf')
      upload('cardápio.pdf', pdf)
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:put) do |path, body, **_|
        expect(path).to eq("/api/templates/#{id}/draft/files/arquivos/card%C3%A1pio.pdf")
        expect(Base64.strict_decode64(body[:content_base64])).to eq(pdf)
      end
    end

    it 'keeps only the base name and refuses hidden names' do
      allow(Rt::EngineClient).to receive(:put).and_return({})
      upload('../../etc/passwd.txt', 'x')
      expect(Rt::EngineClient).to have_received(:put).with("/api/templates/#{id}/draft/files/arquivos/passwd.txt", anything, anything)
      upload('.oculto.pdf', pdf)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns the engine validation message to the user' do
      error = Rt::EngineClient::Error.new('422 x', status: 422,
                                                   body: { 'detail' => 'Arquivos .exe não são aceitos', 'problems' => [{ 'code' => 'bad_extension', 'message' => 'Arquivos .exe não são aceitos' }] })
      allow(Rt::EngineClient).to receive(:put).and_raise(error)
      upload('virus.exe', 'MZ')
      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['code']).to eq('invalid_file')
      expect(body['message']).to include('.exe')
      expect(body['problems'].first['code']).to eq('bad_extension')
    end

    it 'turns other engine failures into a generic error' do
      allow(Rt::EngineClient).to receive(:put).and_raise(Rt::EngineClient::Error.new('500', status: 500, body: nil))
      upload('a.pdf', pdf)
      expect(response).to have_http_status(:bad_gateway)
    end

    it 'rejects files over 10 MB before calling the engine' do
      allow(Rt::EngineClient).to receive(:put)
      upload('grande.pdf', 'a' * ((10 * 1024 * 1024) + 1))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('file_too_large')
      expect(Rt::EngineClient).not_to have_received(:put)
    end

    it 'requires the edit permission and a UUID' do
      allow(Rt::EngineClient).to receive(:put).and_return({})
      upload('a.pdf', pdf, user: agent)
      expect(response).to have_http_status(:forbidden)
      post "/api/v1/accounts/#{account.id}/rt_ai/agents/abc/upload_file", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'deletes only paths inside arquivos/' do
      allow(Rt::EngineClient).to receive(:delete).and_return('ok' => true)
      delete "#{base}/delete_file", params: { path: 'arquivos/cardapio.pdf' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(Rt::EngineClient).to have_received(:delete).with("/api/templates/#{id}/draft/files/arquivos/cardapio.pdf", anything)
      ['AGENTE.md', 'arquivos/../AGENTE.md', 'skills/x/SKILL.md'].each do |bad|
        delete "#{base}/delete_file", params: { path: bad }, headers: admin.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
