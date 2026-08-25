# Produto-10 (25/08/2026): reaproveita o `oauth-browser` já construído pro
# produto-08 (Claude/Codex) -- mesmo serviço, cross-repo (chatwoot-rt chama
# o Cloud Run do agent-platform), só que aqui o resultado esperado é
# `cookies`, não `code`/`state` (ver oauth-browser/app.py, provedores
# facebook_web/instagram_web).
class SocialUnofficial::NavegadorRemotoService
  class NavegadorRemotoError < StandardError; end

  def initialize(provider:)
    @provider = provider
  end

  def iniciar_sessao
    response = HTTParty.post(
      "#{oauth_browser_url}/sessions",
      headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{oauth_browser_admin_token}" },
      body: { provider: provider }.to_json,
      timeout: 35
    )
    raise NavegadorRemotoError, "falha ao abrir navegador remoto: HTTP #{response.code}" unless response.success?

    dados = response.parsed_response
    ws_base = oauth_browser_url.sub('https://', 'wss://').sub('http://', 'ws://')
    {
      session_id: dados['session_id'],
      ws_url: "#{ws_base}/sessions/#{dados['session_id']}/stream?token=#{dados['ws_token']}"
    }
  rescue HTTParty::Error, Errno::ECONNREFUSED, Net::OpenTimeout => e
    raise NavegadorRemotoError, "navegador remoto inacessível: #{e.message}"
  end

  private

  attr_reader :provider

  def oauth_browser_url
    ENV.fetch('OAUTH_BROWSER_URL') { raise NavegadorRemotoError, 'OAUTH_BROWSER_URL não configurada' }
  end

  def oauth_browser_admin_token
    ENV.fetch('OAUTH_BROWSER_ADMIN_TOKEN') { raise NavegadorRemotoError, 'OAUTH_BROWSER_ADMIN_TOKEN não configurado' }
  end
end
