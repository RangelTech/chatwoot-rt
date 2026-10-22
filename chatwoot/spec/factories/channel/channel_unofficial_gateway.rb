# frozen_string_literal: true

FactoryBot.define do
  factory :channel_instagram_unofficial, class: 'Channel::InstagramUnofficial' do
    account
    connection_id { SecureRandom.uuid }
    state { 'connected' }
    webhook_secret { SecureRandom.hex(32) }
    inbox { association :inbox, account: account }
  end

  factory :channel_messenger_unofficial, class: 'Channel::MessengerUnofficial' do
    account
    connection_id { SecureRandom.uuid }
    state { 'connected' }
    webhook_secret { SecureRandom.hex(32) }
    inbox { association :inbox, account: account }
  end

  factory :channel_whatsapp_unofficial, class: 'Channel::WhatsappUnofficial' do
    account
    connection_id { SecureRandom.uuid }
    state { 'connected' }
    webhook_secret { SecureRandom.hex(32) }
    inbox { association :inbox, account: account }
  end

  factory :channel_tiktok_unofficial, class: 'Channel::TiktokUnofficial' do
    account
    connection_id { SecureRandom.uuid }
    state { 'connected' }
    webhook_secret { SecureRandom.hex(32) }
    inbox { association :inbox, account: account }
  end

  factory :channel_facebook_unofficial, class: 'Channel::FacebookUnofficial' do
    account
    state { 'reauth_required' }
    inbox { association :inbox, account: account }
  end
end
