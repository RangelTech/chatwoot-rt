require 'rails_helper'

RSpec.describe Wapi::ConnectionTestService do
  let(:channel) { create(:channel_wapi, project_id: 'proj-123', token: 'secret-token') }

  describe '#perform' do
    it 'reports connected when WAPI status endpoint returns a connected status' do
      stub_request(:get, %r{/v1/status\?projectId=proj-123})
        .with(headers: { 'Authorization' => 'Bearer secret-token' })
        .to_return(status: 200, body: { status: 'connected' }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = described_class.new(channel: channel).perform

      expect(result['status']).to eq('connected')
    end

    it 'reports disconnected when WAPI returns a non-connected status' do
      stub_request(:get, %r{/v1/status\?projectId=proj-123})
        .to_return(status: 200, body: { status: 'closed' }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = described_class.new(channel: channel).perform

      expect(result['status']).to eq('disconnected')
    end

    it 'reports error when WAPI returns a non-2xx response' do
      stub_request(:get, %r{/v1/status\?projectId=proj-123})
        .to_return(status: 401, body: { error: 'invalid token' }.to_json)

      result = described_class.new(channel: channel).perform

      expect(result['status']).to eq('error')
    end

    it 'reports error when the request times out or the host is unreachable' do
      stub_request(:get, %r{/v1/status\?projectId=proj-123}).to_timeout

      result = described_class.new(channel: channel).perform

      expect(result['status']).to eq('error')
    end
  end
end
