# Fase CH: canal não oficial conectado pelo gateway de canais (sem cookie, sem polling).
class Channel::MessengerUnofficial < ApplicationRecord
  include UnofficialGatewayChannel

  self.table_name = 'channel_messenger_unofficial'

  def name
    'Messenger Unoficial'
  end
end
