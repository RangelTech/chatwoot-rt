require 'rails_helper'

# Suite de contrato do fork (UPG-0): telemetria desligada, aviso de versao so no Super Admin.
RSpec.describe 'Fork contract: ciclo de atualizacao', type: :request do
  describe Rt::ChatwootHubGuard do
    it 'nao chama o hub do Chatwoot (ping, registro, eventos)' do
      expect(RestClient).not_to receive(:post)

      expect(ChatwootHub.sync_with_hub).to be_nil
      expect(ChatwootHub.register_instance('Empresa', 'Dono', 'dono@example.com')).to be_nil
      expect(ChatwootHub.emit_event('evento', {})).to be_nil
    end

    it 'so reabilita com RT_ALLOW_CHATWOOT_HUB=true' do
      with_modified_env(RT_ALLOW_CHATWOOT_HUB: 'true') { expect(described_class.allowed?).to be(true) }
      expect(described_class.allowed?).to be(false)
    end

    it 'mantem DISABLE_TELEMETRY ligado no processo' do
      expect(ENV.fetch('DISABLE_TELEMETRY', nil)).to eq('true')
    end
  end

  describe 'aviso de versao na aplicacao do usuario' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'nao expoe latest_chatwoot_version nem com a chave no Redis' do
      Redis::Alfred.set(Redis::Alfred::LATEST_CHATWOOT_VERSION, '99.0.0')

      get "/api/v1/accounts/#{account.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['latest_chatwoot_version']).to be_nil
    ensure
      Redis::Alfred.delete(Redis::Alfred::LATEST_CHATWOOT_VERSION)
    end
  end

  describe Rt::UpgradeStatus do
    before { $alfred.with { |conn| conn.del(described_class::LATEST_KEY, described_class::REHEARSALS_KEY) } }

    it 'marca atualizacao disponivel so quando o upstream e mais novo que a base' do
      allow(described_class).to receive(:base_version).and_return('4.16.2')
      described_class.record_latest(version: '4.17.0')
      expect(described_class.snapshot[:update_available]).to be(true)

      described_class.record_latest(version: '4.16.2')
      expect(described_class.snapshot[:update_available]).to be(false)
    end

    it 'guarda o historico de ensaios, mais recente primeiro' do
      described_class.record_rehearsal(target: '4.17.0', status: 'conflicts', conflicts: 3, files: 40)
      described_class.record_rehearsal(target: '4.17.1', status: 'clean', conflicts: 0, files: 41)

      expect(described_class.rehearsals.pluck('target')).to eq(%w[4.17.1 4.17.0])
      expect(described_class.snapshot[:last_rehearsal]).to include('status' => 'clean', 'conflicts' => 0)
    end
  end

  describe Rt::UpstreamVersionCheck do
    before { $alfred.with { |conn| conn.del(Rt::UpgradeStatus::LATEST_KEY) } }

    def stub_release(body, status: 200)
      stub_request(:get, described_class::URL.to_s).to_return(status: status, body: body.to_json,
                                                              headers: { 'Content-Type' => 'application/json' })
    end

    it 'registra a ultima versao estavel sem enviar dados da instalacao' do
      stub = stub_release(tag_name: 'v4.19.0', html_url: 'https://github.com/chatwoot/chatwoot/releases/tag/v4.19.0')

      described_class.call

      expect(stub).to have_been_requested
      expect(Rt::UpgradeStatus.latest).to include('version' => '4.19.0')
      expect(WebMock).not_to have_requested(:any, /hub\.2\.chatwoot\.com/)
    end

    it 'ignora pre-lancamentos e tags nao estaveis' do
      stub_release(tag_name: 'v4.20.0-rc1', prerelease: true)
      described_class.call
      expect(Rt::UpgradeStatus.latest).to be_nil

      stub_release(tag_name: 'v4.20.0-beta')
      described_class.call
      expect(Rt::UpgradeStatus.latest).to be_nil
    end

    it 'falha em silencio quando o upstream nao responde' do
      stub_release({}, status: 500)
      expect { described_class.call }.not_to raise_error
      expect(Rt::UpgradeStatus.latest).to be_nil
    end
  end

  describe 'POST /rt/upgrade_rehearsals' do
    let(:params) { { target: '4.17.0', status: 'conflicts', conflicts: 5, files: 61 } }

    before { $alfred.with { |conn| conn.del(Rt::UpgradeStatus::REHEARSALS_KEY) } }

    it 'responde 404 sem token configurado' do
      post '/rt/upgrade_rehearsals', params: params, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'rejeita token errado e aceita o certo' do
      with_modified_env(RT_UPGRADE_REPORT_TOKEN: 'segredo-do-ensaio') do
        post '/rt/upgrade_rehearsals', params: params, headers: { 'Authorization' => 'Bearer errado' }, as: :json
        expect(response).to have_http_status(:unauthorized)

        post '/rt/upgrade_rehearsals', params: params, headers: { 'Authorization' => 'Bearer segredo-do-ensaio' }, as: :json
        expect(response).to have_http_status(:created)
        expect(Rt::UpgradeStatus.snapshot[:last_rehearsal]).to include('target' => '4.17.0', 'conflicts' => 5)
      end
    end

    it 'rejeita status desconhecido' do
      with_modified_env(RT_UPGRADE_REPORT_TOKEN: 'segredo-do-ensaio') do
        post '/rt/upgrade_rehearsals', params: params.merge(status: 'xpto'),
                                       headers: { 'Authorization' => 'Bearer segredo-do-ensaio' }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end

RSpec.describe 'Fork contract: cartao do Super Admin', type: :view do
  before { $alfred.with { |conn| conn.del(Rt::UpgradeStatus::LATEST_KEY, Rt::UpgradeStatus::REHEARSALS_KEY) } }

  it 'mostra versao base, ultima estavel, verificacao e ensaio' do
    allow(Rt::UpgradeStatus).to receive(:base_version).and_return('4.16.2')
    Rt::UpgradeStatus.record_latest(version: '4.17.0')
    Rt::UpgradeStatus.record_rehearsal(target: '4.17.0', status: 'conflicts', conflicts: 7, files: 70)

    render partial: 'super_admin/instance_statuses/chatwoot_update'

    expect(rendered).to include('Atualização do Chatwoot', '4.16.2', '4.17.0', '7 conflito(s)')
  end

  it 'funciona antes da primeira verificacao' do
    render partial: 'super_admin/instance_statuses/chatwoot_update'
    expect(rendered).to include('ainda não verificada', 'nenhum ensaio registrado')
  end
end
