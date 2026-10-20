require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Approvals', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:approval_id) { SecureRandom.uuid }
  let(:base) { "/api/v1/accounts/#{account.id}/rt_ai/approvals" }

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
  end

  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo') { example.run }
  end

  def reader_headers
    reader = create(:user, account: account, role: :agent)
    Rt::AiGrant.create!(account_user: reader.account_users.find_by(account: account), role_key: 'leitor')
    reader.create_new_auth_token
  end

  it 'lists the pending approvals through the engine' do
    allow(Rt::EngineClient).to receive(:get).and_return([{ 'approval_id' => approval_id, 'chat_id' => 'c' }])
    get base, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(Rt::EngineClient).to have_received(:get).with('/api/approvals/pending', claims: hash_including(aud: 'ui'))
  end

  it 'forwards the decision to the engine' do
    allow(Rt::EngineClient).to receive(:post).and_return({ 'status' => 'approved' })
    post "#{base}/#{approval_id}/decide", params: { decision: 'approve' }, headers: headers, as: :json
    expect(response.parsed_body['status']).to eq('approved')
    expect(Rt::EngineClient).to have_received(:post).with("/api/approvals/#{approval_id}", { decision: 'approve' }, claims: anything)
  end

  it 'rejects an unknown decision and a non-UUID id' do
    post "#{base}/#{approval_id}/decide", params: { decision: 'maybe' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/abc/decide", params: { decision: 'deny' }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'maps engine 404 (someone else\'s approval) and 409 (already answered)' do
    allow(Rt::EngineClient).to receive(:post).and_raise(Rt::EngineClient::Error.new('404', status: 404))
    post "#{base}/#{approval_id}/decide", params: { decision: 'deny' }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    allow(Rt::EngineClient).to receive(:post).and_raise(Rt::EngineClient::Error.new('409', status: 409))
    post "#{base}/#{approval_id}/decide", params: { decision: 'deny' }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'denies the reader the decision but lets the reader see the list' do
    post "#{base}/#{approval_id}/decide", params: { decision: 'approve' }, headers: reader_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    allow(Rt::EngineClient).to receive(:get).and_return([])
    get base, headers: reader_headers, as: :json
    expect(response).to have_http_status(:success)
  end
end
