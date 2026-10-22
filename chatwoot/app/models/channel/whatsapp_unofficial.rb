# Fase CH: canal não oficial conectado pelo gateway de canais (sem cookie, sem polling).
class Channel::WhatsappUnofficial < ApplicationRecord
  include UnofficialGatewayChannel

  self.table_name = 'channel_whatsapp_unofficial'

  def name
    'WhatsApp Unoficial'
  end
end
