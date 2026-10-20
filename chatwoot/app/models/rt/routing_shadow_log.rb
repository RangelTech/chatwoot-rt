# Fase F: divergencias do modo sombra (decisao do legado x decisao derivada do Chatwoot).
class Rt::RoutingShadowLog < ApplicationRecord
  self.table_name = 'rt_routing_shadow_log'

  scope :diverged, -> { where(diverged: true) }
end
