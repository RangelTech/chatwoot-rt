require 'rails_helper'

RSpec.describe Rt::AccountUserRevocation do
  around do |example|
    with_modified_env(RT_ENGINE_URL: 'http://engine.test', RT_UI_CONTEXT_SECRET: 'segredo-de-teste') { example.run }
  end

  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let!(:account_user) { create(:account_user, account: account, user: user) }

  def revoked_events
    Rt::OutboxEvent.where(account_id: account.id, kind: 'member_revoked')
  end

  it 'enqueues member_revoked with the user when the AccountUser is removed' do
    account_user.destroy!
    event = revoked_events.sole
    expect(event.user_id).to eq(user.id)
    expect(event.occurred_at).to be_present
  end

  it 'does not enqueue when the whole account is destroyed (deprovision covers it)' do
    allow(Rt::EngineClient).to receive(:post).and_return({})
    perform_enqueued_jobs { account.destroy! }
    expect(revoked_events).to be_empty
  end

  it 'does nothing when the engine is not configured' do
    with_modified_env(RT_ENGINE_URL: '') do
      account_user.destroy!
      expect(revoked_events).to be_empty
    end
  end

  describe 'delivery' do
    before { account_user.destroy! }

    it 'posts to the engine member-revoked endpoint with the removal time' do
      allow(Rt::EngineClient).to receive(:post).and_return({})
      Rt::OutboxJob.perform_now
      expect(Rt::EngineClient).to have_received(:post).with(
        '/internal/ui/member-revoked',
        hash_including(account_id: account.id, chatwoot_user_id: user.id, revoked_at: be_a(Float))
      )
      expect(revoked_events.sole.state).to eq('done')
    end

    it 'skips the call when the person was added back before delivery' do
      create(:account_user, account: account, user: user)
      allow(Rt::EngineClient).to receive(:post)
      Rt::OutboxJob.perform_now
      expect(Rt::EngineClient).not_to have_received(:post).with('/internal/ui/member-revoked', anything)
      expect(revoked_events.sole.state).to eq('done')
    end

    it 'retries with backoff when the engine fails' do
      allow(Rt::EngineClient).to receive(:post).and_raise(Rt::EngineClient::Error, '503')
      Rt::OutboxJob.perform_now
      event = revoked_events.sole
      expect(event.state).to eq('pending')
      expect(event.attempts).to eq(1)
    end
  end
end
