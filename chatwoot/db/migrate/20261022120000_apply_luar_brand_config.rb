# U-6 (spec 10): grava a marca LUAR em InstallationConfig. O valor efetivo vem do banco, entao
# o YAML e a env nao bastam em instalacao existente. Idempotente; mesmos valores de rt:brand:apply
# (RtBrand::VALUES). Nao toca dados de tenant. Rollback: valores do `rails rt:brand:snapshot`.
class ApplyLuarBrandConfig < ActiveRecord::Migration[7.1]
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

  def up
    VALUES.each do |name, value|
      config = InstallationConfig.find_or_initialize_by(name: name)
      next if config.persisted? && config.value == value

      config.value = value
      config.save!
    end
    clear_cache
  end

  def down; end

  private

  def clear_cache
    GlobalConfig.clear_cache
  rescue StandardError => e
    say "cache de GlobalConfig nao limpo: #{e.class}"
  end
end
