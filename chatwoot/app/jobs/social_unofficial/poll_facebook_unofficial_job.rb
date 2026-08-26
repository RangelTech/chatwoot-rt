# Produto-05 (25-26/08/2026): mesmo motivo do PollInstagramUnofficialJob --
# sem webhook, precisa de polling agendado. Um canal de cada vez, nunca em
# paralelo (mesmo ritmo sequencial já usado em toda a stack).
class SocialUnofficial::PollFacebookUnofficialJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Channel::FacebookUnofficial.find_each do |channel|
      next unless channel.connected?

      SocialUnofficial::PollFacebookUnofficialService.new(channel: channel).perform
    end
  end
end
