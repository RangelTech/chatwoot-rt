# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Canais não oficiais (gateway)' do
  %i[channel_instagram_unofficial channel_messenger_unofficial channel_whatsapp_unofficial channel_tiktok_unofficial].each do |factory|
    describe factory do
      let(:channel) { create(factory) }

      it 'é válido e conecta pelo estado' do
        expect(channel).to be_valid
        expect(channel).to be_connected
        expect(channel.inbox).to be_present
        expect(channel.account.public_send("#{channel.provider}_unofficial_channels")).to include(channel)
      end

      it 'não exige cookies' do
        expect(channel.has_attribute?(:cookies) ? channel[:cookies] : nil).to be_nil
      end

      it 'rejeita estado desconhecido' do
        channel.state = 'qualquer'
        expect(channel).not_to be_valid
      end

      it 'connection_id é único' do
        other = build(factory, connection_id: channel.connection_id)
        expect(other).not_to be_valid
      end

      it 'monta a URL do webhook por tipo e id' do
        expect(channel.callback_url).to end_with("/webhooks/channels/#{channel.class.name.demodulize.underscore}/#{channel.id}")
      end

      it 'aplica estado de conexão e erro' do
        channel.apply_connection_state!('degraded', error_code: 'timeout')
        expect(channel.reload).to have_attributes(state: 'degraded', last_error_code: 'timeout')
        expect(channel).not_to be_connected
      end

      it 'ignora estado inválido em apply_connection_state!' do
        channel.apply_connection_state!('bogus')
        expect(channel.reload.state).to eq('connected')
      end
    end
  end

  it 'legado Facebook sem cookie nem connection_id é válido e não conecta' do
    legacy = create(:channel_facebook_unofficial)
    expect(legacy).to be_valid
    expect(legacy).to be_reauth_required
    expect(legacy).not_to be_connected
  end

  it 'gera segredo do webhook de 64 hex' do
    channel = build(:channel_tiktok_unofficial, webhook_secret: nil)
    channel.generate_webhook_secret!
    expect(channel.webhook_secret).to match(/\A\h{64}\z/)
  end

  it 'resolve classes por tipo e por provedor' do
    expect(UnofficialGatewayChannel.channel_class_for_type('whatsapp_unofficial')).to eq(Channel::WhatsappUnofficial)
    expect(UnofficialGatewayChannel.channel_class_for_provider('messenger')).to eq(Channel::MessengerUnofficial)
    expect(UnofficialGatewayChannel.channel_class_for_type('wapi')).to be_nil
  end

  it 'inbox expõe unofficial_gateway?' do
    expect(create(:channel_instagram_unofficial).inbox).to be_unofficial_gateway
    expect(create(:channel_wapi).inbox).not_to be_unofficial_gateway
  end
end

RSpec.describe 'Migração de dados dos canais legados com cookie' do
  require Rails.root.join('db/migrate/20261020000200_legacy_unofficial_cookies_to_reauth_required.rb')

  it 'marca reauth_required sem apagar cookie nem histórico, e é idempotente' do
    legacy = create(:channel_instagram_unofficial, state: nil, connection_id: nil)
    legacy.update_columns(cookies: 'segredo-legado') # rubocop:disable Rails/SkipsModelValidations
    inbox_id = legacy.inbox.id
    migrated = create(:channel_facebook_unofficial, state: 'connected')

    2.times { LegacyUnofficialCookiesToReauthRequired.new.up }

    expect(legacy.reload).to have_attributes(state: 'reauth_required', last_error_code: 'legacy_cookie_session')
    expect(legacy[:cookies]).to eq('segredo-legado')
    expect(Inbox.find(inbox_id)).to be_present
    expect(migrated.reload.state).to eq('connected')
  end
end
