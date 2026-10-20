require 'rails_helper'

RSpec.describe Rt::Routing::LegacyMigration do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:ai_team) { create(:team, account: account, name: 'IA', allow_auto_assign: false) }
  let(:human_team) { create(:team, account: account, name: 'Humano') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: human_team, status: :open) }

  let(:configuration) do
    {
      inbox_id: inbox.id,
      ai_team_id: ai_team.id,
      handoff_team_id: human_team.id,
      template_id: 'template-legado',
      autopilot: true
    }
  end

  before do
    allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(true)
  end

  it 'migra de modo idempotente, guarda o legado e volta sem apagar o registro Rt' do
    result = described_class.apply(
      account: account,
      configurations: [configuration],
      conversations: [{ conversation_id: conversation.id, state: 'ai_active' }]
    )

    expect(result).to include(inboxes: 1, conversations_migrated: 1)
    entry = Rt::InboxEntryQueue.find_by!(inbox: inbox)
    expect(entry).to have_attributes(team: ai_team, routing_mode: 'sombra')
    expect(entry.legacy_snapshot.dig('legacy_bridge_config', 'template_id')).to eq('template-legado')
    expect(entry.legacy_snapshot.dig('conversation_teams', conversation.id.to_s)).to eq(human_team.id)
    expect(conversation.reload.team).to eq(ai_team)

    described_class.apply(
      account: account,
      configurations: [configuration],
      conversations: [{ conversation_id: conversation.id, state: 'ai_active' }]
    )
    expect(Rt::InboxEntryQueue.where(inbox: inbox).count).to eq(1)
    expect(Rt::QueueBinding.where(team: ai_team).count).to eq(1)

    rollback = described_class.rollback(account: account, inbox_id: inbox.id)
    expect(rollback).to include(inbox_id: inbox.id, conversations_restored: 1)
    expect(conversation.reload.team).to eq(human_team)
    expect(entry.reload.routing_mode).to eq('legado')
    expect(Rt::QueueBinding.find_by!(team: ai_team).respondent_kind).to eq('humano')
  end

  it 'recusa uma fila de IA que ainda tem pessoas, sem alterar a caixa' do
    user = create(:user, account: account, role: :agent)
    create(:team_member, team: ai_team, user: user)

    expect do
      described_class.apply(account: account, configurations: [configuration], conversations: [])
    end.to raise_error(ArgumentError, /membros humanos/)
    expect(Rt::InboxEntryQueue.find_by(inbox: inbox)).to be_nil
  end

  it 'mantem conversa humana na fila humana durante a sombra' do
    described_class.apply(
      account: account,
      configurations: [configuration],
      conversations: [{ conversation_id: conversation.id, state: 'human_active' }]
    )

    expect(conversation.reload.team).to eq(human_team)
  end
end
