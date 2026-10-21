# Telemetria desligada (spec 10, UPG-0): nenhuma chamada ao hub do Chatwoot (ping com métricas, registro,
# eventos) sai desta instalação. Só reabilita com RT_ALLOW_CHATWOOT_HUB=true (nunca em produção).
module Rt::ChatwootHubGuard
  def self.allowed?
    ENV['RT_ALLOW_CHATWOOT_HUB'].to_s == 'true'
  end

  def sync_with_hub
    Rt::ChatwootHubGuard.allowed? ? super : nil
  end

  def register_instance(*)
    Rt::ChatwootHubGuard.allowed? ? super : nil
  end

  def emit_event(*)
    Rt::ChatwootHubGuard.allowed? ? super : nil
  end
end
