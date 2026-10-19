# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe Rake::Task, 'rt:brand' do # rubocop:disable RSpec/DescribeMethod, RSpec/SpecFilePathFormat
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.load_tasks unless described_class.task_defined?('rt:brand:apply')
  end

  let(:apply) { described_class['rt:brand:apply'] }
  let(:snapshot) { described_class['rt:brand:snapshot'] }

  before do
    apply.reenable
    snapshot.reenable
    InstallationConfig.where(name: RtBrand::SNAPSHOT_KEYS).destroy_all
  end

  def config_value(name)
    InstallationConfig.find_by(name: name)&.value
  end

  describe 'rt:brand:apply' do
    it 'grava os valores LUAR' do
      expect { apply.invoke }.to output(/LUAR brand applied/).to_stdout

      RtBrand::VALUES.each { |name, value| expect(config_value(name)).to eq(value) }
    end

    it 'sobrescreve valores antigos' do
      InstallationConfig.create!(name: 'BRAND_NAME', value: 'RAtende')

      expect { apply.invoke }.to output(/BRAND_NAME/).to_stdout
      expect(config_value('BRAND_NAME')).to eq('LUAR')
    end

    it 'e idempotente: segunda execucao nao altera registros' do
      expect { apply.invoke }.to output.to_stdout
      apply.reenable
      before_state = InstallationConfig.where(name: RtBrand::VALUES.keys).pluck(:name, :updated_at).sort

      expect { apply.invoke }.to output(/already applied/).to_stdout

      expect(InstallationConfig.where(name: RtBrand::VALUES.keys).pluck(:name, :updated_at).sort).to eq(before_state)
      expect(InstallationConfig.where(name: RtBrand::VALUES.keys).count).to eq(RtBrand::VALUES.size)
    end

    it 'nao toca em URLs de marca' do
      InstallationConfig.create!(name: 'BRAND_URL', value: 'https://www.chatwoot.com')

      expect { apply.invoke }.to output.to_stdout
      expect(config_value('BRAND_URL')).to eq('https://www.chatwoot.com')
    end

    it 'limpa o cache de GlobalConfig' do
      allow(GlobalConfig).to receive(:clear_cache).and_call_original

      expect { apply.invoke }.to output.to_stdout
      expect(GlobalConfig).to have_received(:clear_cache).at_least(:once)
    end
  end

  describe 'rt:brand:snapshot' do
    it 'imprime os valores atuais em JSON e nulo para ausentes' do
      InstallationConfig.create!(name: 'BRAND_NAME', value: 'RAtende')

      output = capture_stdout { snapshot.invoke }
      data = JSON.parse(output)

      expect(data['BRAND_NAME']['value']).to eq('RAtende')
      expect(data['LOGO']).to be_nil
      expect(data.keys).to match_array(RtBrand::SNAPSHOT_KEYS)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
