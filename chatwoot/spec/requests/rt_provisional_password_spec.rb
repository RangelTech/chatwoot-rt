require 'rails_helper'

RSpec.describe 'Provisional password blocks the API', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  it 'allows only the profile until the password is changed' do
    Rt::ProvisionalPassword.issue!(user)
    get "/api/v1/accounts/#{account.id}/agents", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['code']).to eq('must_change_password')
    get '/api/v1/profile', headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'does not affect regular users' do
    get "/api/v1/accounts/#{account.id}/agents", headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end
end
