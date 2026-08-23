require 'rails_helper'

RSpec.describe 'Inboxes API - provision_evolution', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    stub_const('ENV', ENV.to_hash.merge(
      'BRIDGE_URL' => 'https://bridge.example.test',
      'BRIDGE_ADMIN_TOKEN' => 'admin-token'
    ))
  end

  def stub_bridge(instance_name: "evolution-#{account.id}")
    stub_request(:post, 'https://bridge.example.test/admin/evolution/provision')
      .to_return(
        status: 200,
        body: { status: 'ready', instance_name: instance_name, api_url: 'https://evo.example', api_key: 'k' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe 'POST /api/v1/accounts/{account.id}/inboxes/provision_evolution' do
    it 'returns unauthorized for an unauthenticated caller' do
      post "/api/v1/accounts/#{account.id}/inboxes/provision_evolution"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects an agent -- only administrators can provision channels' do
      stub_bridge

      post "/api/v1/accounts/#{account.id}/inboxes/provision_evolution",
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.evolution_api_channels.count).to eq(0)
    end

    it 'creates the inbox without the caller ever sending instance_name/api_url/api_key' do
      stub_bridge

      post "/api/v1/accounts/#{account.id}/inboxes/provision_evolution",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['id']).to be_present
      expect(body.to_s).not_to include('api_key')
    end

    it 'never lets one account provision or reuse the instance belonging to another' do
      other_account = create(:account)
      other_admin = create(:user, account: other_account, role: :administrator)
      stub_request(:post, 'https://bridge.example.test/admin/evolution/provision')
        .with(body: hash_including(chatwoot_account_id: other_account.id))
        .to_return(
          status: 200,
          body: { status: 'ready', instance_name: 'evolution-other', api_url: 'https://evo.example', api_key: 'k1' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      stub_request(:post, 'https://bridge.example.test/admin/evolution/provision')
        .with(body: hash_including(chatwoot_account_id: account.id))
        .to_return(
          status: 200,
          body: { status: 'ready', instance_name: 'evolution-mine', api_url: 'https://evo.example', api_key: 'k2' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      post "/api/v1/accounts/#{other_account.id}/inboxes/provision_evolution",
           headers: other_admin.create_new_auth_token, as: :json
      post "/api/v1/accounts/#{account.id}/inboxes/provision_evolution",
           headers: admin.create_new_auth_token, as: :json

      expect(account.evolution_api_channels.pluck(:instance_name)).to eq(['evolution-mine'])
      expect(other_account.evolution_api_channels.pluck(:instance_name)).to eq(['evolution-other'])
    end

    it 'surfaces a provisioning failure as 422, not a 500' do
      stub_request(:post, 'https://bridge.example.test/admin/evolution/provision')
        .to_return(status: 502, body: { detail: 'falhou' }.to_json)

      post "/api/v1/accounts/#{account.id}/inboxes/provision_evolution",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
