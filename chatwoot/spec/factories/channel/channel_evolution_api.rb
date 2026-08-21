FactoryBot.define do
  factory :channel_evolution_api, class: 'Channel::EvolutionApi' do
    instance_name { "evolution-#{SecureRandom.hex(6)}" }
    api_url { 'https://evolution.example.test' }
    api_key { SecureRandom.hex(20) }
    inbox
    account
  end
end
