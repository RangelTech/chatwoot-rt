require 'rails_helper'

RSpec.describe 'Webhooks::WapiController', type: :request do
  describe 'POST /webhooks/wapi/{:project_id}' do
    context 'when the project_id does not match any channel' do
      it 'returns not_found' do
        post '/webhooks/wapi/unknown-project', params: { verify_token: 'whatever' }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the channel exists' do
      let(:channel) { create(:channel_wapi, project_id: 'proj-123', webhook_verify_token: 'correct-token') }

      before { channel }

      it 'rejects requests with a missing or wrong verify_token' do
        post '/webhooks/wapi/proj-123', params: { verify_token: 'wrong-token' }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'enqueues the events job and returns ok when the token matches' do
        allow(Webhooks::WapiEventsJob).to receive(:perform_later)

        post '/webhooks/wapi/proj-123', params: { verify_token: 'correct-token', type: 'message' }

        expect(Webhooks::WapiEventsJob).to have_received(:perform_later).with(
          project_id: 'proj-123',
          params: hash_including('type' => 'message')
        )
        expect(response).to have_http_status(:success)
      end

      it 'accepts the verify token via header instead of a param' do
        allow(Webhooks::WapiEventsJob).to receive(:perform_later)

        post '/webhooks/wapi/proj-123', params: { type: 'message' }, headers: { 'X-Wapi-Verify-Token' => 'correct-token' }

        expect(response).to have_http_status(:success)
      end
    end
  end
end
