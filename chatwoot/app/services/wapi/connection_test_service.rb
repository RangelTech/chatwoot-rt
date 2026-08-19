# Calls the WAPI provider's own status/ping endpoint using the project id + token
# configured on the channel and normalizes the result into the small hash we
# persist on Channel::Wapi#connection_status (consumed by the green/red health
# indicator in the UI).
#
# WAPI's exact status endpoint/response shape isn't publicly documented in a
# stable way, so the base URL and path are configurable via GlobalConfig so ops
# can point this at whatever the real provider contract turns out to be without
# a code deploy.
class Wapi::ConnectionTestService
  class ApiError < StandardError; end

  DEFAULT_BASE_URI = 'https://api.w-api.app'.freeze
  STATUS_PATH = '/v1/status'.freeze
  TIMEOUT = 10

  def initialize(channel:)
    @channel = channel
  end

  def perform
    response = HTTParty.get(
      status_url,
      headers: { 'Authorization' => "Bearer #{@channel.token}", 'Accept' => 'application/json' },
      timeout: TIMEOUT
    )

    build_result(response)
  rescue HTTParty::Error, Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
    { 'status' => 'error', 'message' => e.message, 'checked_at' => Time.current.iso8601 }
  end

  private

  def status_url
    base_uri = GlobalConfigService.load('WAPI_BASE_URI', DEFAULT_BASE_URI)
    "#{base_uri}#{STATUS_PATH}?projectId=#{CGI.escape(@channel.project_id)}"
  end

  def build_result(response)
    if response.success?
      {
        'status' => connected_status(response.parsed_response),
        'raw' => response.parsed_response.is_a?(Hash) ? response.parsed_response : {},
        'checked_at' => Time.current.iso8601
      }
    else
      {
        'status' => 'error',
        'message' => "WAPI status endpoint returned HTTP #{response.code}",
        'checked_at' => Time.current.iso8601
      }
    end
  end

  def connected_status(body)
    return 'error' unless body.is_a?(Hash)

    truthy = [true, 'true', 'connected', 'CONNECTED', 'open', 'OPEN'].freeze
    truthy.include?(body['status'] || body['connected']) ? 'connected' : 'disconnected'
  end
end
