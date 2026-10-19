require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtKanban', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/rt_kanban" }

  def make_card(box, owner_team: nil)
    conversation = create(:conversation, account: account, inbox: box, team: owner_team)
    RtKanban::EnsureCard.call(conversation)
  end

  before do
    RtKanban::EnsureBoard.call(account).update!(enabled: true)
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe 'visibility (KAN-02)' do
    it 'shows admin everything, agent only own inbox or team, nobody else' do
      mine = make_card(inbox)
      other = make_card(other_inbox)
      team = create(:team, account: account)
      create(:team_member, team: team, user: agent)
      by_team = make_card(other_inbox, owner_team: team)
      board = RtKanban::Board.find_by(account_id: account.id)
      stage = board.initial_stage

      get "#{base}/cards", params: { stage_id: stage.id }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['items'].pluck('id')).to contain_exactly(mine.id, other.id, by_team.id)

      get "#{base}/cards", params: { stage_id: stage.id }, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['items'].pluck('id')).to contain_exactly(mine.id, by_team.id)

      outsider = create(:user)
      get "#{base}/cards", params: { stage_id: stage.id }, headers: outsider.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'counts only visible cards per stage and hides the board while disabled for agents' do
      make_card(inbox)
      make_card(other_inbox)
      get "#{base}/board", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['stages'].first['count_visible']).to eq(1)
      RtKanban::Board.find_by(account_id: account.id).update!(enabled: false)
      get "#{base}/board", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      get "#{base}/board", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end

  describe 'moving cards (KAN-04, KAN-05, KAN-07)' do
    let(:board) { RtKanban::Board.find_by(account_id: account.id) }
    let(:target) { board.stages.find_by(name: 'Concluído') }

    def move(user, card, body)
      patch "#{base}/cards/#{card.id}/move", params: body, headers: user.create_new_auth_token, as: :json
    end

    it 'moves, bumps versions, writes one event and does not touch the conversation status' do
      card = make_card(inbox)
      conversation = card.conversation
      status_before = conversation.status
      move(agent, card, to_stage_id: target.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['card']).to include('stage_id' => target.id, 'lock_version' => 1)
      expect(RtKanban::Event.where(action: 'moved', card_id_snapshot: card.id).count).to eq(1)
      expect(conversation.reload.status).to eq(status_before)
    end

    it 'returns 409 for a stale version and applies only one of two simultaneous moves' do
      card = make_card(inbox)
      move(agent, card, to_stage_id: target.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      move(admin, card, to_stage_id: board.initial_stage.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:conflict)
      expect(RtKanban::Event.where(action: 'moved', card_id_snapshot: card.id).count).to eq(1)
    end

    it 'replays the same idempotency key without a second event and rejects the key with another body' do
      card = make_card(inbox)
      key = SecureRandom.hex(8)
      body = { to_stage_id: target.id, expected_lock_version: 0, idempotency_key: key }
      move(agent, card, body)
      move(agent, card, body)
      expect(response).to have_http_status(:success)
      expect(RtKanban::Event.where(action: 'moved', card_id_snapshot: card.id).count).to eq(1)
      move(agent, card, body.merge(to_stage_id: board.stages.second.id))
      expect(response).to have_http_status(:conflict)
    end

    it 'orders a card before an anchor and rejects an anchor from another stage' do
      first = make_card(inbox)
      second = make_card(inbox)
      initial = board.initial_stage
      move(agent, second, to_stage_id: initial.id, before_card_id: first.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:success)
      expect(second.reload.position).to be < first.reload.position
      move(agent, first, to_stage_id: target.id, before_card_id: second.id, expected_lock_version: first.lock_version,
                         idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'hides a card the user cannot see (404) and refuses a stage of another account (KAN-03)' do
      hidden = make_card(other_inbox)
      move(agent, hidden, to_stage_id: target.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:not_found)
      other_account = create(:account)
      foreign_stage = RtKanban::EnsureBoard.call(other_account).initial_stage
      card = make_card(inbox)
      move(agent, card, to_stage_id: foreign_stage.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload.lock_version).to eq(0)
    end

    it 'keeps Concluído independent from the conversation status (resolve and reopen)' do
      card = make_card(inbox)
      move(agent, card, to_stage_id: target.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      card.conversation.resolved!
      card.conversation.open!
      expect(card.reload.stage_id).to eq(target.id)
    end
  end

  describe 'stages and board admin' do
    it 'lets only admins manage stages and enable the board; initial stage cannot be removed' do
      post "#{base}/stages", params: { name: 'Proposta', color: '#112233' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/stages", params: { name: 'Proposta', color: '#112233' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      initial = RtKanban::Board.find_by(account_id: account.id).initial_stage
      delete "#{base}/stages/#{initial.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'requires a destination to delete a stage that has cards' do
      stage = RtKanban::Board.find_by(account_id: account.id).stages.find_by(name: 'Em atendimento')
      card = make_card(inbox)
      card.update_columns(stage_id: stage.id) # rubocop:disable Rails/SkipsModelValidations
      delete "#{base}/stages/#{stage.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)
      delete "#{base}/stages/#{stage.id}", params: { move_to_stage_id: card.board.initial_stage.id },
                                           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(card.reload.stage_id).to eq(card.board.initial_stage.id)
    end
  end

  it 'paginates with an opaque cursor and caps the limit' do
    3.times { make_card(inbox) }
    stage = RtKanban::Board.find_by(account_id: account.id).initial_stage
    get "#{base}/cards", params: { stage_id: stage.id, limit: 2 }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['items'].size).to eq(2)
    cursor = response.parsed_body['next_cursor']
    expect(cursor).to be_present
    get "#{base}/cards", params: { stage_id: stage.id, limit: 2, cursor: cursor }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['items'].size).to eq(1)
    get "#{base}/cards", params: { stage_id: stage.id, cursor: 'lixo' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:bad_request)
  end
end
