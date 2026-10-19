# frozen_string_literal: true

# Rebrand LUAR da instalacao. O valor efetivo vem de InstallationConfig (banco),
# nao do config/installation_config.yml, entao o YAML sozinho nao basta.
#
#   bundle exec rails rt:brand:snapshot   # imprime valores atuais (para rollback)
#   bundle exec rails rt:brand:apply      # grava a marca LUAR (idempotente)
#
#   bundle exec rails rt:brand:verify     # falha se houver "Chatwoot" visivel ou ativo ausente
module RtBrand
  VALUES = {
    'INSTALLATION_NAME' => 'LUAR',
    'BRAND_NAME' => 'LUAR',
    'LOGO' => '/brand-assets/logo.svg',
    'LOGO_DARK' => '/brand-assets/logo_dark.svg',
    'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.svg',
    'BRAND_URL' => 'https://chat.rangeltech.net',
    'WIDGET_BRAND_URL' => 'https://chat.rangeltech.net',
    'TERMS_URL' => 'https://chat.rangeltech.net/termos-de-servico',
    'PRIVACY_URL' => 'https://chat.rangeltech.net/politica-de-privacidade'
  }.freeze

  ASSETS = (
    %w[logo.svg logo_dark.svg logo_thumbnail.svg logo_mono.svg logo_mono_white.svg
       logo_thumbnail_mono.svg logo_thumbnail_mono_white.svg logo-email.png logo-email-dark.png].map { |f| "public/brand-assets/#{f}" } +
    %w[favicon-16x16 favicon-32x32 favicon-96x96 favicon-512x512 favicon-badge-16x16 favicon-badge-32x32 favicon-badge-96x96
       android-icon-192x192 maskable-icon-192x192 maskable-icon-512x512 apple-icon-180x180 apple-icon ms-icon-144x144].map { |f| "public/#{f}.png" } +
    %w[public/favicon.ico public/manifest.json public/browserconfig.xml]
  ).freeze

  # Arquivos com texto visivel ao usuario (pt-BR e en) e e-mails.
  VISIBLE_GLOBS = %w[
    app/javascript/dashboard/i18n/locale/{en,pt_BR}/*.json
    app/javascript/widget/i18n/locale/{en,pt_BR}.json
    app/javascript/survey/i18n/locale/{en,pt_BR}.json
    config/locales/{en,pt_BR}.yml
    app/views/mailers/**/*.liquid
    app/views/layouts/mailer/*.liquid
    public/manifest.json
  ].freeze

  # Ocorrencias tecnicas permitidas (contrato de SDK, CNAME, identificador SAML, chave de i18n).
  ALLOWED = [
    /window\.chatwoot\w*/, /chatwoot\.help/, %r{www\.chatwoot\.com/(terms|privacy-policy)},
    /Unique identifier for Chatwoot as the Service Provider/, /Identificador exclusivo do Chatwoot/,
    /UPDATE_CHATWOOT/, /latestChatwootVersion/
  ].freeze

  def self.visible_offenses(root = Rails.root)
    VISIBLE_GLOBS.flat_map { |glob| Dir.glob(root.join(glob)) }.flat_map do |file|
      File.foreach(file).with_index(1).filter_map do |line, number|
        cleaned = ALLOWED.reduce(line) { |text, pattern| text.gsub(pattern, '') }
        "#{Pathname(file).relative_path_from(root)}:#{number}: #{line.strip[0, 120]}" if cleaned.match?(/chatwoot/i)
      end
    end
  end

  def self.missing_assets(root = Rails.root)
    ASSETS.reject { |path| root.join(path).file? && root.join(path).size.positive? }
  end

  SNAPSHOT_KEYS = (VALUES.keys + %w[DISPLAY_MANIFEST]).freeze
end

namespace :rt do # rubocop:disable Metrics/BlockLength
  namespace :brand do # rubocop:disable Metrics/BlockLength
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

    desc 'Falha se houver "Chatwoot" em texto visivel (pt-BR/en), ativo ausente ou config divergente'
    task verify: :environment do
      problems = RtBrand.visible_offenses.map { |o| "texto: #{o}" }
      problems += RtBrand.missing_assets.map { |a| "ativo ausente: #{a}" }
      RtBrand::VALUES.each do |name, value|
        current = InstallationConfig.find_by(name: name)&.value
        next if current == value

        problems << "config #{name}=#{current.inspect} (esperado #{value.inspect})"
      end
      abort("rt:brand:verify falhou:\n  #{problems.join("\n  ")}") if problems.any?

      puts 'rt:brand:verify ok'
    end
  end
end
