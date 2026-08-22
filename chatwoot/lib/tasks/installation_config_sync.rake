# frozen_string_literal: true

namespace :installation_config do
  desc 'Synchronize Meta credentials from environment variables into InstallationConfig'
  task sync_meta: :environment do
    meta_keys = %w[
      FB_APP_ID
      FB_APP_SECRET
      FB_VERIFY_TOKEN
      INSTAGRAM_APP_ID
      INSTAGRAM_APP_SECRET
      INSTAGRAM_VERIFY_TOKEN
      WHATSAPP_APP_ID
      WHATSAPP_APP_SECRET
      WHATSAPP_CONFIGURATION_ID
    ].freeze

    missing = meta_keys.select { |name| ENV[name].blank? }
    abort "Missing required Meta environment variables: #{missing.join(', ')}" if missing.any?

    values = meta_keys.index_with { |name| ENV.fetch(name) }
    # Chatwoot still checks the legacy alias for Instagram webhook verification.
    values['IG_VERIFY_TOKEN'] = values.fetch('INSTAGRAM_VERIFY_TOKEN')

    values.each do |name, value|
      config = InstallationConfig.find_or_initialize_by(name: name)
      changed = config.new_record? || config.value != value || config.locked?
      config.value = value
      config.locked = false
      config.save! if changed
    end

    GlobalConfig.clear_cache
    puts "Synchronized #{values.keys.join(', ')} from environment"
  end
end
