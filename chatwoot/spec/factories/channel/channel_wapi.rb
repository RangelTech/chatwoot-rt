# frozen_string_literal: true

FactoryBot.define do
  factory :channel_wapi, class: 'Channel::Wapi' do
    project_id { SecureRandom.uuid }
    token { SecureRandom.hex(20) }
    inbox
    account
  end
end
