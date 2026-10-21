require 'net/http'

# Verificação de versão NOSSA (spec 10, UPG-0): lê só a lista pública de lançamentos do upstream.
# Não envia identificador, métricas nem qualquer dado da instalação (sem corpo, User-Agent genérico).
class Rt::UpstreamVersionCheck
  URL = URI('https://api.github.com/repos/chatwoot/chatwoot/releases/latest')
  STABLE = /\Av?(\d+\.\d+\.\d+)\z/

  def self.call
    new.call
  end

  def call
    release = fetch
    return nil if release.blank? || release['draft'] || release['prerelease']

    match = STABLE.match(release['tag_name'].to_s)
    return nil unless match

    Rt::UpgradeStatus.record_latest(version: match[1], url: release['html_url'])
  end

  private

  def fetch
    request = Net::HTTP::Get.new(URL, 'Accept' => 'application/vnd.github+json', 'User-Agent' => 'luar-version-check')
    response = Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.warn("[rt] verificacao de versao upstream falhou: #{e.class}")
    nil
  end
end
