require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Members', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:id/rt_ai/members' do
    it 'denies agents' do
      get "/api/v1/accounts/#{account.id}/rt_ai/members", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists members with their AI profile for administrators' do
      agent
      get "/api/v1/accounts/#{account.id}/rt_ai/members", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      keys = response.parsed_body['members'].pluck('ai_role_key')
      expect(keys).to contain_exactly('administrador_ia', 'operador')
    end
  end

  describe 'PUT /api/v1/accounts/:id/rt_ai/members/:id' do
    it 'sets and clears a grant' do
      member = agent.account_users.find_by(account: account)
      put "/api/v1/accounts/#{account.id}/rt_ai/members/#{member.id}",
          params: { role_key: 'gestor' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['ai_role_key']).to eq('gestor')
      put "/api/v1/accounts/#{account.id}/rt_ai/members/#{member.id}",
          params: { role_key: 'operador' }, headers: admin.create_new_auth_token, as: :json
      expect(member.reload.rt_ai_grant).to be_nil
    end

    it 'does not touch members of another account' do
      other = create(:account_user)
      put "/api/v1/accounts/#{account.id}/rt_ai/members/#{other.id}",
          params: { role_key: 'gestor' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
