# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendReplyJob, 'canais não oficiais' do
  {
    channel_instagram_unofficial: 'Channel::InstagramUnofficial',
    channel_messenger_unofficial: 'Channel::MessengerUnofficial',
    channel_whatsapp_unofficial: 'Channel::WhatsappUnofficial',
    channel_tiktok_unofficial: 'Channel::TiktokUnofficial',
    channel_facebook_unofficial: 'Channel::FacebookUnofficial'
  }.each do |factory, klass|
    it "mapeia #{klass} para Channels::SendOnUnofficialService" do
      expect(described_class::CHANNEL_SERVICES[klass]).to eq(Channels::SendOnUnofficialService)
      channel = create(factory)
      conversation = create(:conversation, inbox: channel.inbox, account: channel.account)
      message = create(:message, inbox: channel.inbox, account: channel.account, message_type: :outgoing, conversation: conversation)
      service = instance_double(Channels::SendOnUnofficialService, perform: true)
      allow(Channels::SendOnUnofficialService).to receive(:new).with(message: message).and_return(service)
      described_class.perform_now(message.id)
      expect(service).to have_received(:perform)
    end
  end

  it 'não mapeia mais os serviços de cookie' do
    expect(described_class::CHANNEL_SERVICES.values.map(&:to_s)).not_to include(a_string_matching(/SocialUnofficial/))
  end

  it 'não agenda mais polling de cookie' do
    schedule = YAML.safe_load_file(Rails.root.join('config/schedule.yml'))
    expect(schedule.keys).not_to include('poll_instagram_unofficial_job', 'poll_facebook_unofficial_job')
    expect(schedule.values.pluck('class').compact.grep(/PollInstagram|PollFacebook/)).to be_empty
  end
end
