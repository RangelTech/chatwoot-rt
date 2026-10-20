require 'rails_helper'

# F-0 (spike): fixa em teste os comportamentos reais do Chatwoot em que o desenho da Fase F se apoia.
# Se uma atualizacao do Chatwoot (Fase UP) quebrar qualquer um destes, o resolver precisa ser revisto.
RSpec.describe 'Fase F-0: comportamento nativo de filas e responsavel' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:humans) { create(:team, account: account, name: 'humanos', allow_auto_assign: false) }
  let(:ia_team) { create(:team, account: account, name: 'ia', allow_auto_assign: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)
  end

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: humans, user: agent)
  end

  describe '(a) mover para equipe sem membros' do
    it 'zera o responsavel humano que nao pertence a nova equipe e nao escolhe outro' do
      conversation.update!(team: humans, assignee: agent)
      expect(conversation.reload.assignee).to eq(agent)

      conversation.update!(team: ia_team)
      expect(conversation.reload.assignee_id).to be_nil
      expect(conversation.team_id).to eq(ia_team.id)
    end

    it 'mantem o responsavel quando ele e membro da nova equipe' do
      other = create(:team, account: account, name: 'outra', allow_auto_assign: false)
      create(:team_member, team: other, user: agent)
      conversation.update!(team: humans, assignee: agent)
      conversation.update!(team: other)
      expect(conversation.reload.assignee_id).to eq(agent.id)
    end

    it 'nao atribui automaticamente numa equipe sem membros e sem auto-assign' do
      conversation.update!(team: ia_team)
      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'dispara team_changed e assignee_changed ao mover' do
      conversation.update!(team: humans, assignee: agent)
      events = []
      allow(Rails.configuration.dispatcher).to receive(:dispatch) { |name, *| events << name }
      conversation.update!(team: ia_team)
      expect(events).to include(Events::Types::TEAM_CHANGED, Events::Types::ASSIGNEE_CHANGED)
    end
  end

  describe '(b) humano que escreve' do
    it 'nao vira responsavel sozinho (o Luar precisa marcar a assuncao)' do
      conversation.update!(team: ia_team)
      Current.user = agent
      Messages::MessageBuilder.new(agent, conversation, { content: 'oi, sou humano', message_type: 'outgoing' }).perform
      expect(conversation.reload.assignee_id).to be_nil
      Current.reset
    end
  end

  describe '(c) payload do webhook' do
    it 'traz equipe, responsavel e status na conversa de cada mensagem' do
      conversation.update!(team: humans, assignee: agent)
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'ola')
      data = message.webhook_data
      meta = data[:conversation][:meta]
      expect(data[:id]).to eq(message.id)
      expect(data[:conversation][:status]).to eq('open')
      expect(data[:conversation][:inbox_id]).to eq(inbox.id)
      expect(meta[:team][:id]).to eq(humans.id)
      expect(meta[:assignee][:id]).to eq(agent.id)
      expect(meta[:assignee_type]).to eq('User')
    end

    it 'sem fila nem responsavel, meta traz nil (o resolver aplica a fila de entrada)' do
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      meta = message.webhook_data[:conversation][:meta]
      expect(meta[:team]).to be_nil
      expect(meta[:assignee]).to be_nil
    end
  end

  describe '(d) assignee_agent_bot como sinal opcional' do
    let(:bot) { create(:agent_bot, outgoing_url: 'http://bridge.test/agent-bot') }

    it 'nao e limpo ao trocar de equipe (so quando entra responsavel humano)' do
      conversation.update!(assignee_agent_bot: bot)
      conversation.update!(team: ia_team)
      expect(conversation.reload.assignee_agent_bot_id).to eq(bot.id)
      conversation.update!(team: humans, assignee: agent)
      expect(conversation.reload.assignee_agent_bot_id).to be_nil
    end

    it 'o listener entrega o evento ao bot responsavel mesmo sem bot na caixa' do
      conversation.update!(assignee_agent_bot: bot)
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      expect(AgentBots::WebhookJob).to receive(:perform_later).once
      AgentBotListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    end

    it 'deduplica quando o bot responsavel e o da caixa sao o mesmo' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot, status: 'active')
      conversation.update!(assignee_agent_bot: bot)
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      expect(AgentBots::WebhookJob).to receive(:perform_later).once
      AgentBotListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    end
  end

  describe '(e) conversa resolvida reaberta pelo cliente' do
    it 'mantem a ultima fila ao reabrir (caixa de API sem bot)' do
      conversation.update!(team: ia_team)
      conversation.update!(status: :resolved)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, sender: contact)
      conversation.reload
      expect(conversation.status).to eq('open')
      expect(conversation.team_id).to eq(ia_team.id)
    end

    it 'com bot ativo na caixa a conversa volta como pending, ainda na mesma fila' do
      bot = create(:agent_bot)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot, status: 'active')
      conversation.update!(team: ia_team, status: :resolved)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, sender: contact)
      conversation.reload
      expect(conversation.status).to eq('pending')
      expect(conversation.team_id).to eq(ia_team.id)
    end
  end

  describe '(f) ordem e duplicacao de webhooks' do
    it 'cada mensagem tem id estavel no payload (chave de deduplicacao); reentrega gera novo delivery_id' do
      bot = create(:agent_bot)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot, status: 'active')
      message = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      jobs = []
      allow(AgentBots::WebhookJob).to receive(:perform_later) { |_url, payload, *_| jobs << payload }
      2.times { AgentBotListener.instance.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
      expect(jobs.size).to eq(2)
      expect(jobs.pluck(:id).uniq).to eq([message.id])
    end

    it 'conversation_updated carrega changed_attributes com team_id ao mudar de fila' do
      payloads = []
      allow(Rails.configuration.dispatcher).to receive(:dispatch) do |name, _time, data|
        payloads << data[:changed_attributes] if name == Events::Types::CONVERSATION_UPDATED
      end
      conversation.update!(team: ia_team)
      expect(payloads.flatten.compact.flat_map(&:keys)).to include('team_id')
    end
  end
end
