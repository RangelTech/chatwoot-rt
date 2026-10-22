require 'rails_helper'

# F-1: validacoes (fila de IA sem membros, sem auto-assign, template publicado do tenant), guardas e modo por caixa.
RSpec.describe 'Fase F-1: modelos de fila' do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account, name: 'ia-vendas', allow_auto_assign: false) }

  def ia_binding(team:, **attrs)
    Rt::QueueBinding.new({ account: account, team: team, respondent_kind: 'ia', template_id: 'tpl-1', mode: 'piloto' }.merge(attrs))
  end

  describe Rt::QueueBinding do
    before { allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(true) }

    it 'aceita fila de IA vazia, sem auto-assign, com agente publicado' do
      expect(ia_binding(team: team)).to be_valid
    end

    it 'recusa fila de IA com membro humano' do
      create(:team_member, team: team, user: agent)
      expect(ia_binding(team: team)).not_to be_valid
    end

    it 'recusa fila de IA com allow_auto_assign ligado' do
      expect(ia_binding(team: create(:team, account: account, name: 'x', allow_auto_assign: true))).not_to be_valid
    end

    it 'recusa template de outro tenant ou nao publicado' do
      allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(false)
      binding = ia_binding(team: team)
      expect(binding).not_to be_valid
      expect(binding.errors[:template_id]).to be_present
    end

    it 'aceita quando o motor nao responde (desconhecido); o resolver trata como nao publicado' do
      allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(nil)
      expect(ia_binding(team: team)).to be_valid
    end

    it 'exige template na fila de IA' do
      expect(ia_binding(team: team, template_id: nil)).not_to be_valid
    end

    it 'fila humana limpa os campos de IA' do
      binding = Rt::QueueBinding.create!(account: account, team: team, respondent_kind: 'humano', template_id: 'x', mode: 'piloto')
      expect(binding.template_id).to be_nil
      expect(binding.mode).to eq('desligado')
    end

    it 'recusa destinos fora da conta ou a propria fila' do
      other_account_team = create(:team, account: create(:account), name: 'z')
      expect(ia_binding(team: team, allowed_destination_team_ids: [other_account_team.id])).not_to be_valid
      expect(ia_binding(team: team, allowed_destination_team_ids: [team.id])).not_to be_valid
      ok = create(:team, account: account, name: 'humanos')
      expect(ia_binding(team: team, allowed_destination_team_ids: [ok.id])).to be_valid
    end

    it 'uma fila so tem um vinculo' do
      ia_binding(team: team).save!
      expect(ia_binding(team: team)).not_to be_valid
    end
  end

  describe 'guardas de membro humano na fila de IA' do
    before do
      allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(true)
      ia_binding(team: team).save!
    end

    it 'TeamMember.create e invalido (UI/API/Super Admin/console)' do
      member = TeamMember.new(team: team, user: agent)
      expect(member).not_to be_valid
      expect { TeamMember.create!(team: team, user: agent) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'Team#add_members levanta RecordInvalid (a API responde 422)' do
      expect { team.add_members([agent.id]) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(team.reload.members).to be_empty
    end

    it 'nao liga allow_auto_assign' do
      expect(team.update(allow_auto_assign: true)).to be(false)
    end

    it 'fila humana continua aceitando membros' do
      human = create(:team, account: account, name: 'humanos')
      Rt::QueueBinding.create!(account: account, team: human, respondent_kind: 'humano')
      expect(human.add_members([agent.id])).to eq([agent])
    end
  end

  describe 'excluir fila com conversas abertas' do
    before do
      allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(true)
      ia_binding(team: team).save!
    end

    let!(:conversation) { create(:conversation, account: account, team: team, status: :open) }

    it 'exige destino' do
      expect(team.destroy).to be(false)
      expect(Team.exists?(team.id)).to be(true)
    end

    it 'move as abertas para o destino escolhido e exclui' do
      destination = create(:team, account: account, name: 'humanos')
      team.rt_move_open_conversations_to = destination.id
      expect(team.destroy).to be_truthy
      expect(conversation.reload.team_id).to eq(destination.id)
    end

    it 'exclui sem destino quando so ha conversas resolvidas' do
      conversation.update!(status: :resolved)
      expect(team.destroy).to be_truthy
    end
  end

  describe Rt::InboxEntryQueue do
    let(:inbox) { create(:inbox, account: account) }

    it 'sem registro o modo e legado' do
      expect(described_class.mode_for(inbox.id)).to eq('legado')
    end

    it 'sombra/filas exigem fila de entrada' do
      expect(described_class.new(account: account, inbox: inbox, routing_mode: 'sombra')).not_to be_valid
      expect(described_class.new(account: account, inbox: inbox, team: team, routing_mode: 'sombra')).to be_valid
    end

    it 'recusa caixa ou fila de outra conta' do
      foreign = create(:team, account: create(:account), name: 'f')
      expect(described_class.new(account: account, inbox: inbox, team: foreign, routing_mode: 'filas')).not_to be_valid
    end
  end

  describe Rt::RoutingEvent do
    it 'e append-only' do
      conversation = create(:conversation, account: account)
      event = described_class.record!(conversation: conversation, from_team_id: nil, to_team_id: team.id, actor_kind: 'human', actor_id: agent.id)
      expect(event.update(reason: 'x')).to be(false)
      expect(event.destroy).to be(false)
    end
  end

  describe 'permissoes ai.inbox_routing' do
    it 'view para gestor e manage so para administrador de IA' do
      expect(Rt::AiRoles::GESTOR).to include('ai.inbox_routing.view')
      expect(Rt::AiRoles::GESTOR).not_to include('ai.inbox_routing.manage')
      expect(Rt::AiRoles::ALL).to include('ai.inbox_routing.manage')
    end
  end
end
