# Produto-10 (25/08/2026): sem webhook (ver PollInstagramUnofficialService),
# então precisa de polling agendado -- roda a cada 2 minutos
# (config/schedule.yml), um canal de cada vez, nunca em paralelo (evita
# rate limit e mantém o ritmo sequencial já usado em toda a stack).
class SocialUnofficial::PollInstagramUnofficialJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channel::InstagramUnofficial.find_each do |channel|
      next unless channel.connected?

      SocialUnofficial::PollInstagramUnofficialService.new(channel: channel).perform
    end
  end
end
