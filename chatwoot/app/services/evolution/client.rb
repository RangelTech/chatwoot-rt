class Evolution::Client
  class ApiError < StandardError; end

  def initialize(channel:)
    @channel = channel
  end

  def connect
    create_instance
    configure_webhook
    connection_result(get("instance/connect/#{instance_name}"))
  end

  def reconnect
    response = post("instance/restart/#{instance_name}")
    return connection_result(response) if response.success?

    # A disconnected Baileys session cannot be restarted by some Evolution v2
    # releases. Asking the existing instance for a new QR keeps the Chatwoot
    # inbox, contacts and conversation history untouched.
    connection_result(get("instance/connect/#{instance_name}"))
  end

  def send_text(to:, text:)
    response = post("message/sendText/#{instance_name}", number: to, text: text)
    raise_api_error(response) unless response.success?

    response.parsed_response.dig('key', 'id') || response.parsed_response.dig('message', 'key', 'id')
  end

  def connection_state
    response = get("instance/connectionState/#{instance_name}")
    raise_api_error(response) unless response.success?

    response.parsed_response.dig('instance', 'state')
  end

  private

  attr_reader :channel

  delegate :api_key, :api_url, :callback_url, :instance_name, to: :channel

  def create_instance
    response = post('instance/create', instanceName: instance_name, integration: 'WHATSAPP-BAILEYS', qrcode: true)
    return if response.success? || response.code == 409

    raise_api_error(response)
  end

  def configure_webhook
    response = post("webhook/set/#{instance_name}", url: callback_url, events: %w[MESSAGES_UPSERT CONNECTION_UPDATE])
    raise_api_error(response) unless response.success?
  end

  def connection_result(response)
    raise_api_error(response) unless response.success?

    body = response.parsed_response
    {
      qr_code: body.dig('qrcode', 'base64'),
      connection_status: {
        'state' => body.dig('instance', 'state') || body.dig('instance', 'status') || connection_state,
        'source' => 'provider',
        'checked_at' => Time.current.iso8601
      }
    }
  end

  # Achado real (produto-05 seção 9c, teste de conexão contra host inexistente):
  # HTTParty deixa erro de rede (DNS não resolve, connection refused, timeout)
  # subir como exceção própria da stdlib/rede (Socket::ResolutionError,
  # Errno::ECONNREFUSED, Net::OpenTimeout, ...), não como ApiError -- o
  # controller só captura ApiError (rescue Evolution::Client::ApiError), então
  # qualquer falha de rede virava 500 puro em vez do erro tratado que o
  # wizard/health indicator espera. Container Evolution por tenant (seção 4)
  # ainda vai ficar fora do ar às vezes na vida real -- isso não pode 500.
  def get(path)
    HTTParty.get(url(path), headers: headers, timeout: 15)
  rescue StandardError => e
    raise ApiError, "Evolution API unreachable: #{e.message}"
  end

  def post(path, body = {})
    HTTParty.post(url(path), headers: headers, body: body.to_json, timeout: 15)
  rescue StandardError => e
    raise ApiError, "Evolution API unreachable: #{e.message}"
  end

  def url(path)
    "#{api_url.chomp('/')}/#{path}"
  end

  def headers
    { 'Content-Type' => 'application/json', 'apikey' => api_key }
  end

  def raise_api_error(response)
    message = response.parsed_response&.dig('message') || "Evolution API returned HTTP #{response.code}"
    raise ApiError, message
  end
end
