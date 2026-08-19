require 'rails_helper'

RSpec.describe Channel::Wapi do
  describe 'validations' do
    it 'requires project_id and token' do
      channel = described_class.new
      expect(channel).not_to be_valid
      expect(channel.errors[:project_id]).to be_present
      expect(channel.errors[:token]).to be_present
    end

    it 'requires project_id to be unique' do
      existing = create(:channel_wapi)
      duplicate = build(:channel_wapi, project_id: existing.project_id, account: existing.account)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:project_id]).to be_present
    end
  end

  describe '#name' do
    it 'returns WAPI' do
      expect(create(:channel_wapi).name).to eq('WAPI')
    end
  end

  describe '#ensure_webhook_verify_token' do
    it 'auto-generates a webhook_verify_token before validation' do
      channel = create(:channel_wapi)
      expect(channel.webhook_verify_token).to be_present
    end

    it 'does not override an explicitly set token' do
      channel = create(:channel_wapi, webhook_verify_token: 'my-custom-token')
      expect(channel.webhook_verify_token).to eq('my-custom-token')
    end
  end

  describe '#callback_url' do
    it 'includes the project_id so the tenant can paste it into the WAPI panel' do
      channel = create(:channel_wapi, project_id: 'proj-123')
      expect(channel.callback_url).to include('/webhooks/wapi/proj-123')
    end
  end

  describe '#test_connection!' do
    let(:channel) { create(:channel_wapi) }

    it 'persists the connection status returned by the connection test service' do
      allow(Wapi::ConnectionTestService).to receive(:new).with(channel: channel).and_return(
        instance_double(Wapi::ConnectionTestService, perform: { 'status' => 'connected' })
      )

      result = channel.test_connection!

      expect(result).to eq({ 'status' => 'connected' })
      expect(channel.reload.connection_status).to eq({ 'status' => 'connected' })
      expect(channel.reload.connection_status_checked_at).to be_present
    end
  end

  describe '#connected?' do
    it 'is true only when connection_status status is connected' do
      channel = create(:channel_wapi, connection_status: { 'status' => 'connected' })
      expect(channel).to be_connected

      channel.connection_status = { 'status' => 'disconnected' }
      expect(channel).not_to be_connected
    end
  end
end
