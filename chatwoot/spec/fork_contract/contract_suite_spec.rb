require 'rails_helper'

# Garante que a suite de contrato (lista em spec/fork_contract/CONTRACT_SPECS.txt) continua inteira e
# cobre todas as familias exigidas pelo UPG-3. Remover um arquivo da lista ou do repo falha aqui.
RSpec.describe 'Fork contract: integridade da suite' do
  let(:list_path) { Rails.root.join('spec/fork_contract/CONTRACT_SPECS.txt') }
  let(:listed) { list_path.readlines(chomp: true).reject { |l| l.blank? || l.start_with?('#') } }

  REQUIRED_FAMILIES = {
    'permissoes ai.*' => 'spec/models/rt/ai_roles_spec.rb',
    'ciclo de vida / outbox' => 'spec/models/rt/account_lifecycle_spec.rb',
    'proxy do Luar' => 'spec/requests/rt_luar/proxy_spec.rb',
    'Kanban' => 'spec/controllers/api/v1/accounts/rt_kanban/kanban_api_spec.rb',
    'equipe sem membros (F-0)' => 'spec/fork_contract/team_without_members_spec.rb',
    'marca (rt:brand:verify)' => 'spec/lib/tasks/rt_brand_spec.rb',
    'telemetria e aviso de versao' => 'spec/fork_contract/upgrade_cycle_spec.rb',
    'senha provisoria' => 'spec/models/rt/provisional_password_spec.rb',
    'canais WAPI/Evolution' => 'spec/models/channel/wapi_spec.rb'
  }.freeze

  it 'lista so arquivos que existem' do
    missing = listed.reject { |path| Rails.root.join(path).file? }
    expect(missing).to eq([])
  end

  REQUIRED_FAMILIES.each do |family, path|
    it "inclui a familia #{family}" do
      expect(listed).to include(path)
    end
  end

  it 'tem uma familia de flags por Account coberta' do
    expect(listed.grep(%r{rt_ai/(members|resources)_controller_spec})).not_to be_empty
  end

  it 'nao vaza vocabulario proibido nas mensagens de pt-BR da tela de IA' do
    forbidden = /\b(kernel|hermes|harness|litellm)\b/i
    files = Dir[Rails.root.join('app/javascript/dashboard/routes/dashboard/ragent/**/*.{vue,js}').to_s]
    offenders = files.reject { |f| f.end_with?('.spec.js') }.select do |file|
      File.read(file, encoding: 'utf-8').scan(/>([^<>{]+)</).flatten.any? { |text| text.match?(forbidden) }
    end
    expect(offenders).to eq([])
  end
end
