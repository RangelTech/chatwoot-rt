# Fase CH: canal não oficial conectado pelo gateway de canais (sem cookie, sem polling).
class Channel::TiktokUnofficial < ApplicationRecord
  include UnofficialGatewayChannel

  self.table_name = 'channel_tiktok_unofficial'

  def name
    'TikTok Unoficial'
  end
end
