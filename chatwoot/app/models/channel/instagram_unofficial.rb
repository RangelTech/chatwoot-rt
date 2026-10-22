# Instagram não oficial. Fase CH (20/10/2026): novo miolo -- conexão pelo gateway de
# canais (login `android`: usuário/senha + 2FA), entrada por webhook assinado, saída
# via gateway. A coluna `cookies` do desenho antigo fica SEM USO (nunca apagada, CH-9):
# canais legados com cookie viram `reauth_required` e o usuário reconecta pelo assistente.
class Channel::InstagramUnofficial < ApplicationRecord
  include UnofficialGatewayChannel

  self.table_name = 'channel_instagram_unofficial'

  def name
    'Instagram Unoficial'
  end
end
