class Wapi::Client
  class ApiError < StandardError; end

  DEFAULT_BASE_URI = 'https://api.w-api.app'.freeze

  def initialize(channel:)
    @channel = channel
  end

  def send_text(to:, text:)
    response = HTTParty.post(
      "#{base_uri}/v1/message/send-text",
      headers: { 'Authorization' => "Bearer #{channel.token}", 'Content-Type' => 'application/json' },
      query: { instanceId: channel.project_id },
      body: { phone: to, message: text, messageId: SecureRandom.uuid }.to_json,
      timeout: 15
    )
    raise ApiError, response.parsed_response&.dig('message') || "WAPI returned HTTP #{response.code}" unless response.success?

    response.parsed_response['messageId'] || response.parsed_response['id']
  end

  private

  attr_reader :channel

  def base_uri
    GlobalConfigService.load('WAPI_BASE_URI', DEFAULT_BASE_URI).chomp('/')
  end
end
