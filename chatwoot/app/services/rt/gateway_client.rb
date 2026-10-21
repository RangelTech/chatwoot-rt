require 'net/http'

# BFF do gateway de modelos. O browser nunca recebe o token administrativo nem
# escolhe o tenant: ele é sempre o engine_tenant_id da Account autenticada.
class Rt::GatewayClient
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  def self.get(account:, path:)
    request(Net::HTTP::Get, account: account, path: path)
  end

  def self.post(account:, path:, payload: {})
    request(Net::HTTP::Post, account: account, path: path, payload: payload)
  end

  def self.put(account:, path:, payload: {})
    request(Net::HTTP::Put, account: account, path: path, payload: payload)
  end

  def self.delete(account:, path:)
    request(Net::HTTP::Delete, account: account, path: path)
  end

  def self.request(verb, account:, path:, payload: nil)
    ai = Rt::AiAccount.find_by!(account_id: account.id)
    tenant_id = ai.engine_tenant_id.to_s
    raise Error, 'Tenant do Gateway ainda não foi provisionado' if tenant_id.blank?

    uri = URI.join(ENV.fetch('GATEWAY_BASE_URL'), path)
    req = verb.new(uri, 'Content-Type' => 'application/json', 'X-Admin-Token' => ENV.fetch('GATEWAY_ADMIN_TOKEN'),
                        'X-Tenant-Id' => tenant_id)
    req.body = payload.to_json if payload
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 30) { |http| http.request(req) }
    unless response.is_a?(Net::HTTPSuccess)
      raise Error.new("#{response.code} Gateway indisponível", status: response.code.to_i, body: parse(response.body))
    end

    parse(response.body)
  rescue KeyError => e
    raise Error, "Gateway não configurado: #{e.key}"
  rescue SocketError, SystemCallError, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Gateway inacessível: #{e.class}"
  end

  def self.parse(raw)
    raw.present? ? JSON.parse(raw) : {}
  rescue JSON::ParserError
    {}
  end
end
