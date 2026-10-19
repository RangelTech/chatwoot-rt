# frozen_string_literal: true

# Rebrand LUAR da instalacao. O valor efetivo vem de InstallationConfig (banco),
# nao do config/installation_config.yml, entao o YAML sozinho nao basta.
#
#   bundle exec rails rt:brand:snapshot   # imprime valores atuais (para rollback)
#   bundle exec rails rt:brand:apply      # grava a marca LUAR (idempotente)
#
# BRAND_URL, WIDGET_BRAND_URL, TERMS_URL e PRIVACY_URL ficam de fora de proposito:
# so mudam quando existir uma pagina LUAR real.
module RtBrand
  VALUES = {
    'INSTALLATION_NAME' => 'LUAR',
    'BRAND_NAME' => 'LUAR',
    'LOGO' => '/brand-assets/logo.svg',
    'LOGO_DARK' => '/brand-assets/logo_dark.svg',
    'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.svg'
  }.freeze

  SNAPSHOT_KEYS = (VALUES.keys + %w[BRAND_URL WIDGET_BRAND_URL TERMS_URL PRIVACY_URL DISPLAY_MANIFEST]).freeze
end

namespace :rt do
  namespace :brand do
    desc 'Imprime os valores atuais de marca (sem segredos) em JSON, para rollback'
    task snapshot: :environment do
      snapshot = RtBrand::SNAPSHOT_KEYS.index_with do |name|
        config = InstallationConfig.find_by(name: name)
        config ? { 'value' => config.value, 'locked' => config.locked } : nil
      end
      puts JSON.pretty_generate(snapshot)
    end

    desc 'Aplica a marca LUAR em InstallationConfig (idempotente) e limpa o cache'
    task apply: :environment do
      changed = []
      RtBrand::VALUES.each do |name, value|
        config = InstallationConfig.find_or_initialize_by(name: name)
        next if config.persisted? && config.value == value

        config.value = value
        config.save!
        changed << name
      end

      GlobalConfig.clear_cache
      puts(changed.empty? ? 'LUAR brand already applied; nothing changed' : "LUAR brand applied: #{changed.join(', ')}")
    end
  end
end
