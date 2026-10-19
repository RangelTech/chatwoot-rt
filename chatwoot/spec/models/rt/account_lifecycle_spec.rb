require 'rails_helper'

RSpec.describe Rt::AccountLifecycle do
  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo-de-teste') { example.run }
  end

  it 'enqueues provision when an account is created, suspend/resume on status change, deprovision on destroy' do
    account = create(:account)
    expect(Rt::OutboxEvent.where(account_id: account.id).pluck(:kind)).to eq(['provision'])
    account.update!(status: :suspended)
    account.update!(status: :active)
    account.destroy!
    expect(Rt::OutboxEvent.where(account_id: account.id).order(:id).pluck(:kind)).to eq(%w[provision suspend resume deprovision])
  end

  it 'does nothing when the engine is not configured' do
    with_modified_env(RT_ENGINE_URL: '') do
      account = create(:account)
      expect(Rt::OutboxEvent.where(account_id: account.id)).to be_empty
    end
  end

  it 'delivers events, records the engine tenant and retries with backoff on failure' do
    account = create(:account)
    allow(Rt::EngineClient).to receive(:post).and_raise(Rt::EngineClient::Error, '503 down')
    Rt::OutboxJob.perform_now
    event = Rt::OutboxEvent.find_by(account_id: account.id)
    expect(event.state).to eq('pending')
    expect(event.attempts).to eq(1)
    expect(event.run_at).to be > Time.current

    event.update!(run_at: 1.minute.ago)
    allow(Rt::EngineClient).to receive(:post).and_return('engine_tenant_id' => SecureRandom.uuid)
    Rt::OutboxJob.perform_now
    expect(event.reload.state).to eq('done')
    expect(Rt::AiAccount.find_by(account_id: account.id).ai_state).to eq('active')
  end

  it 'marks the account failed after the attempts are exhausted' do
    account = create(:account)
    Rt::OutboxEvent.where(account_id: account.id).update_all(attempts: Rt::OutboxEvent::MAX_ATTEMPTS - 1) # rubocop:disable Rails/SkipsModelValidations
    allow(Rt::EngineClient).to receive(:post).and_raise(Rt::EngineClient::Error, '500')
    Rt::OutboxJob.perform_now
    expect(Rt::AiAccount.find_by(account_id: account.id).ai_state).to eq('failed')
  end

  it 'signs contexts the engine can verify (same format as the engine)' do
    claims = Rt::EngineClient.install_context
    token = Rt::EngineClient.sign(claims)
    body, sig = token.split('.')
    expect(JSON.parse(Base64.urlsafe_decode64(body))['aud']).to eq('install')
    expect(sig).to be_present
    expect(claims[:exp] - claims[:iat]).to be <= 60
  end
end
