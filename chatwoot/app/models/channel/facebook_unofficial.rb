# Facebook não oficial LEGADO (cookies). Fase CH (20/10/2026): canais existentes viram
# `reauth_required` (cookie não converte em login; conversas e histórico preservados) e o
# novo caminho é Channel::MessengerUnofficial. A coluna `cookies` fica sem uso e só sai
# no U-7, com backup e aceite do dono. Sem polling e sem envio por cookie.
class Channel::FacebookUnofficial < ApplicationRecord
  include UnofficialGatewayChannel

  self.table_name = 'channel_facebook_unofficial'

  def name
    'Facebook Unoficial'
  end
end
