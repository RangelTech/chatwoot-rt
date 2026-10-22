# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261022120000_apply_luar_brand_config')

RSpec.describe ApplyLuarBrandConfig do
  before { InstallationConfig.where(name: described_class::VALUES.keys).destroy_all }

  it 'usa os mesmos valores de rt:brand:apply' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('rt:brand:apply')

    expect(described_class::VALUES).to eq(RtBrand::VALUES)
  end

  it 'sobrescreve a marca antiga e e idempotente' do
    InstallationConfig.create!(name: 'INSTALLATION_NAME', value: 'Chatwoot')

    ActiveRecord::Migration.suppress_messages { described_class.new.up }
    expect(InstallationConfig.find_by(name: 'INSTALLATION_NAME').value).to eq('LUAR')
    stamps = InstallationConfig.where(name: described_class::VALUES.keys).pluck(:name, :updated_at).sort

    ActiveRecord::Migration.suppress_messages { described_class.new.up }
    expect(InstallationConfig.where(name: described_class::VALUES.keys).pluck(:name, :updated_at).sort).to eq(stamps)
  end

  it 'Super Admin nao usa o titulo padrao do administrate (nome do modulo Rails)' do
    layout = Rails.root.join('app/views/layouts/super_admin/application.html.erb').read
    nav = Rails.root.join('app/views/super_admin/application/_navigation.html.erb').read

    expect(layout).not_to include('application_title')
    expect(layout).to include('INSTALLATION_NAME')
    expect(nav).not_to match(/>Chatwoot </)
  end
end
