# Estado do ciclo de atualização do Chatwoot (spec 10, Fase UP). Guardado em Redis (efêmero por natureza:
# o job diário e o ensaio semanal o recriam). Aparece só no Super Admin.
class Rt::UpgradeStatus
  LATEST_KEY = 'RT_UPGRADE_LATEST'.freeze
  REHEARSALS_KEY = 'RT_UPGRADE_REHEARSALS'.freeze
  HISTORY_LIMIT = 20

  def self.base_version
    Chatwoot.config[:version].to_s
  end

  def self.record_latest(version:, url: nil, checked_at: Time.current)
    data = { 'version' => version.to_s, 'url' => url, 'checked_at' => checked_at.iso8601 }
    redis { |conn| conn.set(LATEST_KEY, data.to_json) }
    data
  end

  def self.latest
    raw = redis { |conn| conn.get(LATEST_KEY) }
    raw.present? ? JSON.parse(raw) : nil
  rescue JSON::ParserError
    nil
  end

  # `attrs`: target, status ('clean'|'conflicts'|'error'), conflicts, files, summary_url
  def self.record_rehearsal(attrs)
    entry = {
      'target' => attrs[:target].to_s,
      'status' => attrs[:status].to_s,
      'conflicts' => attrs[:conflicts].to_i,
      'files' => attrs[:files].to_i,
      'summary_url' => attrs[:summary_url].presence,
      'at' => Time.current.iso8601
    }
    redis do |conn|
      conn.lpush(REHEARSALS_KEY, entry.to_json)
      conn.ltrim(REHEARSALS_KEY, 0, HISTORY_LIMIT - 1)
    end
    entry
  end

  def self.rehearsals
    redis { |conn| conn.lrange(REHEARSALS_KEY, 0, HISTORY_LIMIT - 1) }.filter_map do |raw|
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
  end

  def self.snapshot
    latest_info = latest
    history = rehearsals
    {
      base_version: base_version,
      latest: latest_info,
      update_available: update_available?(latest_info),
      last_rehearsal: history.first,
      rehearsals: history
    }
  end

  def self.update_available?(latest_info)
    return false if latest_info.blank?

    Gem::Version.new(latest_info['version'].to_s.delete_prefix('v')) > Gem::Version.new(base_version)
  rescue ArgumentError
    false
  end

  def self.redis(&)
    $alfred.with(&)
  end
end
