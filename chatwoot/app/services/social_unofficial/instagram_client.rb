# Produto-10 (25/08/2026): cliente HTTP pro endpoint privado do Instagram
# usado pelo PRÓPRIO site (www.instagram.com/api/v1/direct_v2/...), não a
# API mobile (i.instagram.com -- essa devolve 400 "Prompt has contribution"
# sem os headers de assinatura de app que só o app oficial tem). Testado
# ao vivo 25/08/2026 com cookies reais de login: a rota web aceita cookie
# de sessão + csrftoken puro, sem assinatura nenhuma -- é o que o próprio
# navegador do usuário chama quando ele abre instagram.com/direct/inbox.
#
# Endpoint de envio (`threads/broadcast/text/`) segue o mesmo formato
# documentado por bibliotecas não-oficiais conhecidas (ex. instagrapi) --
# não testado ao vivo ainda (evitar mandar mensagem de teste pra contato
# real sem o dono escolher o destinatário; validar via fluxo real do
# Chatwoot, não script solto).
class SocialUnofficial::InstagramClient
  class ApiError < StandardError; end

  BASE_URL = 'https://www.instagram.com'
  APP_ID = '936619743392459' # ID público do web app do Instagram, usado por qualquer sessão logada no navegador

  def initialize(cookies_jar:)
    @cookies_jar = cookies_jar
  end

  def inbox
    resp = get('/api/v1/direct_v2/inbox/')
    raise_api_error(resp) unless resp.success?

    resp.parsed_response
  end

  def thread_items(thread_id)
    resp = get("/api/v1/direct_v2/threads/#{thread_id}/")
    raise_api_error(resp) unless resp.success?

    resp.parsed_response
  end

  def send_text(thread_id:, text:)
    resp = post(
      '/api/v1/direct_v2/threads/broadcast/text/',
      {
        thread_ids: "[#{thread_id}]",
        text: text,
        client_context: SecureRandom.uuid,
        action: 'send_item'
      }
    )
    raise_api_error(resp) unless resp.success?

    resp.parsed_response
  end

  private

  attr_reader :cookies_jar

  def cookie_header
    cookies_jar.map { |c| "#{c['name']}=#{c['value']}" }.join('; ')
  end

  def csrf_token
    cookies_jar.find { |c| c['name'] == 'csrftoken' }&.dig('value') || ''
  end

  def headers
    {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      'Cookie' => cookie_header,
      'X-IG-App-ID' => APP_ID,
      'X-CSRFToken' => csrf_token,
      'X-Requested-With' => 'XMLHttpRequest',
      'Referer' => "#{BASE_URL}/direct/inbox/"
    }
  end

  def get(path)
    HTTParty.get("#{BASE_URL}#{path}", headers: headers, timeout: 15)
  rescue StandardError => e
    raise ApiError, "Instagram (não oficial) inacessível: #{e.message}"
  end

  def post(path, body)
    HTTParty.post("#{BASE_URL}#{path}", headers: headers, body: body, timeout: 15)
  rescue StandardError => e
    raise ApiError, "Instagram (não oficial) inacessível: #{e.message}"
  end

  def raise_api_error(response)
    raise ApiError, "Instagram (não oficial) devolveu HTTP #{response.code}: #{response.body&.slice(0, 300)}"
  end
end
