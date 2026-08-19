require 'rails_helper'

RSpec.describe 'Inboxes API - WAPI channel', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'POST /api/v1/accounts/{account.id}/inboxes' do
    let(:valid_params) { { name: 'WAPI Inbox', channel: { type: 'wapi', project_id: 'proj-123', token: 'tok-abc' } } }

    it 'creates a wapi inbox when administrator' do
      post "/api/v1/accounts/#{account.id}/inboxes",
           headers: admin.create_new_auth_token,
           params: valid_params,
           as: :json

      expect(response).to have_http_status(:success)
      inbox = account.inboxes.last
      expect(inbox.channel).to be_a(Channel::Wapi)
      expect(inbox.channel.project_id).to eq('proj-123')
    end

    it 'does not allow an agent to create a wapi inbox' do
      post "/api/v1/accounts/#{account.id}/inboxes",
           headers: agent.create_new_auth_token,
           params: valid_params,
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/inboxes/{inbox.id}/test_connection' do
    let(:wapi_channel) { create(:channel_wapi, account: account) }
    let(:inbox) { wapi_channel.inbox }

    it 'returns the live connection status for a wapi inbox' do
      allow_any_instance_of(Channel::Wapi).to receive(:test_connection!).and_return({ 'status' => 'connected' })

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/test_connection",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['status']).to eq('connected')
    end

    it 'returns bad_request for a non-wapi inbox' do
      other_inbox = create(:inbox, account: account)

      post "/api/v1/accounts/#{account.id}/inboxes/#{other_inbox.id}/test_connection",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end
end
