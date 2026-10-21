# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Captura de cookie aposentada (CH-9)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/inboxes" }

  %w[iniciar_social_unofficial concluir_social_unofficial].each do |action|
    it "#{action} responde 410 Gone apontando o novo assistente" do
      post "#{base}/#{action}", headers: admin.create_new_auth_token, params: { provider: 'instagram_web', cookies: [{ name: 'a' }] }, as: :json
      expect(response).to have_http_status(:gone)
      expect(response.parsed_body['replacement']).to eq("/api/v1/accounts/#{account.id}/channel_connections")
    end
  end

  it 'nenhum canal é criado com cookie' do
    expect do
      post "#{base}/concluir_social_unofficial", headers: admin.create_new_auth_token,
                                                  params: { provider: 'instagram_web', cookies: [{ name: 'sessionid', value: 'x' }] }, as: :json
    end.not_to change(Channel::InstagramUnofficial, :count)
  end
end

RSpec.describe 'filter_parameters (Fase CH)' do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it 'redige password, data, code e verification_code' do
    out = filter.filter('password' => 'a', 'data' => { 'password' => 'b' }, 'code' => '123456', 'verification_code' => '9', 'provider' => 'instagram')
    expect(out.values_at('password', 'data', 'code', 'verification_code')).to all(eq('[FILTERED]'))
    expect(out['provider']).to eq('instagram')
  end

  it 'não filtra chaves apenas parecidas (metadata)' do
    expect(filter.filter('metadata' => 'ok', 'country_code' => 'BR')).to eq('metadata' => 'ok', 'country_code' => 'BR')
  end
end
