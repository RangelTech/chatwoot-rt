require 'rails_helper'

# Complementos do Kanban (K2/K5): âncora invisível, reordenar etapas, filtros inválidos, métricas, quadro lazy do admin,
# isolamento entre Accounts e dados hostis tratados como texto.
RSpec.describe 'Api::V1::Accounts::RtKanban extras', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/rt_kanban" }
  let(:board) { RtKanban::Board.find_by(account_id: account.id) }

  def make_card(box)
    RtKanban::EnsureCard.call(create(:conversation, account: account, inbox: box))
  end

  def move(user, card, body)
    patch "#{base}/cards/#{card.id}/move", params: body, headers: user.create_new_auth_token, as: :json
  end

  describe 'quadro lazy do admin (flag por Account)' do
    it 'cria o quadro desligado ao admin e nega ao agente' do
      expect(RtKanban::Board.find_by(account_id: account.id)).to be_nil
      create(:inbox_member, inbox: inbox, user: agent)
      get "#{base}/board", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(RtKanban::Board.find_by(account_id: account.id)).to be_nil
      get "#{base}/board", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['enabled']).to be(false)
      expect(response.parsed_body['stages'].size).to eq(4)
      patch "#{base}/board", params: { enabled: true }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['enabled']).to be(true)
    end
  end

  context 'with the board enabled' do
    before do
      RtKanban::EnsureBoard.call(account).update!(enabled: true)
      create(:inbox_member, inbox: inbox, user: agent)
    end

    it 'recusa âncora de cartão que o agente não pode ver (422) e aceita a visível' do
      mine = make_card(inbox)
      hidden = make_card(other_inbox)
      target = board.initial_stage
      move(agent, mine, to_stage_id: target.id, before_card_id: hidden.id, expected_lock_version: 0,
                        idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('invalid_anchor')
      expect(mine.reload.lock_version).to eq(0)
      move(admin, mine, to_stage_id: target.id, before_card_id: hidden.id, expected_lock_version: 0,
                        idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:success)
    end

    it 'recusa etapa de outra Account com 422 e não escreve nada' do
      other_account = create(:account)
      foreign = RtKanban::EnsureBoard.call(other_account).initial_stage
      card = make_card(inbox)
      move(admin, card, to_stage_id: foreign.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload.stage_id).to eq(board.initial_stage.id)
      expect(RtKanban::Event.where(account_id: account.id, action: 'moved').count).to eq(0)
    end

    it 'não deixa admin de outra Account ler ou mover cartão alheio' do
      card = make_card(inbox)
      other_admin = create(:user, account: create(:account), role: :administrator)
      get "#{base}/board", headers: other_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      move(other_admin, card, to_stage_id: board.initial_stage.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
      expect(response).to have_http_status(:unauthorized)
    end

    it 'devolve 400 para filtros inválidos' do
      stage = board.initial_stage
      [{ status: 'foo' }, { inbox_id: 'abc' }, { assignee_id: '1;drop' }, { status: '' }].each do |extra|
        get "#{base}/cards", params: { stage_id: stage.id }.merge(extra), headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:bad_request), extra.inspect
      end
      get "#{base}/cards", params: { stage_id: stage.id, status: 'all', inbox_id: inbox.id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'trata HTML hostil como texto (JSON cru, sem interpretação) e valida a cor da etapa' do
      contact = create(:contact, account: account, name: '<img src=x onerror=alert(1)>')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      RtKanban::EnsureCard.call(conversation)
      get "#{base}/cards", params: { stage_id: board.initial_stage.id }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['items'].first['conversation']['contact']).to eq('<img src=x onerror=alert(1)>')
      expect(response.media_type).to eq('application/json')
      post "#{base}/stages", params: { name: '<script>x</script>', color: 'red' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{base}/stages", params: { name: '', color: '#112233' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    describe 'reordenar etapas' do
      it 'move a etapa antes da âncora, ao fim, e recusa âncora inexistente' do
        names = -> { board.stages.reload.map(&:name) }
        expect(names.call).to eq(['Novo', 'Em atendimento', 'Aguardando cliente', 'Concluído'])
        done = board.stages.find_by(name: 'Concluído')
        waiting = board.stages.find_by(name: 'Aguardando cliente')
        patch "#{base}/stages/#{done.id}", params: { before_stage_id: waiting.id }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(names.call).to eq(['Novo', 'Em atendimento', 'Concluído', 'Aguardando cliente'])
        patch "#{base}/stages/#{done.id}", params: { before_stage_id: '' }, headers: admin.create_new_auth_token, as: :json
        expect(names.call).to eq(['Novo', 'Em atendimento', 'Aguardando cliente', 'Concluído'])
        patch "#{base}/stages/#{done.id}", params: { before_stage_id: 999_999 }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(names.call).to eq(['Novo', 'Em atendimento', 'Aguardando cliente', 'Concluído'])
        patch "#{base}/stages/#{done.id}", params: { before_stage_id: waiting.id }, headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'sobe a revisão do quadro e mantém posições únicas' do
        before = board.revision
        stage = board.stages.find_by(name: 'Novo')
        patch "#{base}/stages/#{stage.id}", params: { before_stage_id: '' }, headers: admin.create_new_auth_token, as: :json
        expect(board.reload.revision).to eq(before + 1)
        positions = board.stages.reload.map(&:position)
        expect(positions.uniq.size).to eq(positions.size)
        expect(positions).to all(be_positive)
      end
    end

    describe 'métricas (K5)' do
      it 'conta movimentos por resultado só para admin' do
        card = make_card(inbox)
        target = board.stages.find_by(name: 'Concluído')
        move(agent, card, to_stage_id: target.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
        move(agent, card, to_stage_id: target.id, expected_lock_version: 0, idempotency_key: SecureRandom.hex(8))
        expect(response).to have_http_status(:conflict)
        get "#{base}/metrics", headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
        get "#{base}/metrics", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['move_total']).to include('ok' => 1, 'stale_version' => 1)
        expect(body['reconcile']).to include('missing' => 0, 'duplicate' => 0, 'cross_account' => 0)
        expect(body['events_24h']).to be >= 2
      end
    end
  end
end
