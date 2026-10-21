require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::RtAi::Queues', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:human_team) { create(:team, account: account, name: 'atendimento') }

  before do
    Rt::AiAccount.create!(account: account, ai_state: 'active', engine_tenant_id: SecureRandom.uuid, flags: { 'ai_enabled' => true })
    allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(true)
  end

  def url(path = '')
    "/api/v1/accounts/#{account.id}/rt_ai/queues#{path}"
  end

  it 'lists only the current account queues and inbox routing state' do
    foreign = create(:team, account: other_account, name: 'estrangeira')
    Rt::QueueBinding.create!(account: other_account, team: foreign, respondent_kind: 'humano')
    Rt::QueueBinding.create!(account: account, team: human_team, respondent_kind: 'humano', description: 'pessoas')
    Rt::InboxEntryQueue.create!(account: account, inbox: inbox, team: human_team, routing_mode: 'sombra')

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['queues']).to contain_exactly(include('id' => human_team.id, 'respondent_kind' => 'humano'))
    expect(response.parsed_body['inboxes']).to include(include('id' => inbox.id, 'routing_mode' => 'sombra', 'entry_team_id' => human_team.id))
  end

  it 'creates an empty non-auto-assign AI queue with its published agent and allowed destinations' do
    post url, params: {
      name: 'IA vendas', description: 'vendas', respondent_kind: 'ia', template_id: 'agent-vendas',
      mode: 'piloto', destination_team_ids: [human_team.id], account_id: other_account.id
    }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    body = response.parsed_body
    queue = Rt::QueueBinding.find_by!(team_id: body['id'])
    expect(queue).to have_attributes(account: account, respondent_kind: 'ia', template_id: 'agent-vendas', mode: 'piloto')
    expect(queue.allowed_destination_team_ids).to eq([human_team.id])
    expect(queue.team).to have_attributes(allow_auto_assign: false, name: 'ia vendas')
    expect(queue.team.team_members).to be_empty
  end

  it 'sets a per-inbox switch and rejects queue ids from another account' do
    put "#{url}/entry", params: { inbox_id: inbox.id, routing_mode: 'filas', team_id: human_team.id },
                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(Rt::InboxEntryQueue.find_by!(inbox: inbox)).to have_attributes(routing_mode: 'filas', team: human_team)

    foreign = create(:team, account: other_account, name: 'estrangeira')
    put "#{url}/entry", params: { inbox_id: inbox.id, routing_mode: 'filas', team_id: foreign.id },
                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'allows viewing but not queue management by an operator' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    post url, params: { name: 'nao', respondent_kind: 'humano' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
