class GlobalConfigService
  def self.load(config_key, default_value)
    config = GlobalConfig.get(config_key)[config_key]
    # `false` is a legitimate value for boolean installation settings. Treating
    # it as absent caused every dashboard request to clear the complete global
    # config cache while loading ENABLE_ACCOUNT_SIGNUP.
    return config unless config.nil? || config == ''

    # To support migrating existing instance relying on env variables
    # TODO: deprecate this later down the line
    config_value = ENV.fetch(config_key) { default_value }

    return if config_value.nil? || config_value == ''

    i = InstallationConfig.where(name: config_key).first_or_initialize
    return i.value unless i.value.blank?

    i.value = config_value
    i.locked = false
    i.save!
    # To clear a nil value that might have been cached in the previous call.
    # InstallationConfig's after_commit also clears it, but keep this explicit
    # for callers that use a non-standard persistence adapter.
    GlobalConfig.clear_cache
    i.value
  end

  def self.account_signup_enabled?
    load('ENABLE_ACCOUNT_SIGNUP', 'false').to_s != 'false'
  end
end
