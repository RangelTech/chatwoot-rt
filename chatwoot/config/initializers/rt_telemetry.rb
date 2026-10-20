# Fase UP (UPG-0): telemetria desligada por padrão e sem chamadas ao hub do Chatwoot.
ENV['DISABLE_TELEMETRY'] = 'true' unless ENV['RT_ALLOW_CHATWOOT_HUB'].to_s == 'true'

Rails.application.config.to_prepare do
  ChatwootHub.singleton_class.prepend(Rt::ChatwootHubGuard) unless ChatwootHub.singleton_class.include?(Rt::ChatwootHubGuard)
end

# Relatório do ensaio semanal de mesclagem (UPG-5): endpoint autenticado por token, sem sessão.
Rails.application.routes.prepend do
  post '/rt/upgrade_rehearsals', to: 'rt/upgrade_rehearsals#create'
end
