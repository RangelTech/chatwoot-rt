require 'rails_helper'

# Suite de contrato do fork (F-0): comportamento do Chatwoot que o desenho de filas assume.
# Se uma versao do upstream mudar isto, o upgrade nao prossegue ate revisarmos a Fase F.
RSpec.describe 'Fork contract: equipe sem membros e responsavel' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }

  it 'permite atribuir a conversa a uma equipe sem membros, sem responsavel' do
    conversation = create(:conversation, account: account, inbox: inbox)

    conversation.update!(team: team)

    expect(conversation.reload.team).to eq(team)
    expect(conversation.assignee).to be_nil
    expect(team.team_members).to be_empty
  end

  it 'mantem a equipe quando o responsavel e definido ou removido' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agent, inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox, team: team)

    conversation.update!(assignee: agent)
    expect(conversation.reload).to have_attributes(team_id: team.id, assignee_id: agent.id)

    conversation.update!(assignee: nil)
    expect(conversation.reload).to have_attributes(team_id: team.id, assignee_id: nil)
  end
end
