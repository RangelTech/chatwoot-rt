require 'rails_helper'

# F-2 (Resolve + rota interna), F-3 (assuncao/devolucao), F-5 (repasse), F-6 (historico).
RSpec.describe 'Fase F: fluxo de roteamento', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ia_team) { create(:team, account: account, name: 'ia-vendas', allow_auto_assign: false) }
  let(:fin_team) { create(:team, account: account, name: 'financeiro', allow_auto_assign: false) }
  let(:humans) { create(:team, account: account, name: 'humanos', allow_auto_assign: false) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:mode) { 'filas' }

  before do
    allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(true)
    create(:team_member, team: humans, user: agent)
    create(:inbox_member, inbox: inbox, user: agent)
    Rt::QueueBinding.create!(account: account, team: ia_team, respondent_kind: 'ia', template_id: 'tpl-1', mode: 'piloto',
                             allowed_destination_team_ids: [humans.id], description: 'vendas')
    Rt::QueueBinding.create!(account: account, team: humans, respondent_kind: 'humano', description: 'atendimento humano')
    Rt::InboxEntryQueue.create!(account: account, inbox: inbox, team: ia_team, routing_mode: mode)
    Rails.cache.clear
  end

  describe 'Resolve' do
    it 'em filas aplica a fila de entrada e responde ia' do
      result = Rt::Routing::Resolve.call(conversation)
      expect(result).to include(respondent: 'ia', agent: 'tpl-1', applied: true, routing_mode: 'filas')
      expect(conversation.reload.team_id).to eq(ia_team.id)
      expect(Rt::RoutingEvent.where(conversation_id: conversation.id).pluck(:reason)).to include('fila_de_entrada')
    end

    it 'agente desconhecido pelo motor conta como nao publicado (a conversa fica com humanos)' do
      allow(Rt::Routing::TemplateLookup).to receive(:published?).and_return(nil)
      expect(Rt::Routing::Resolve.call(conversation)).to include(respondent: 'humano', reason: 'agente_nao_publicado')
    end

    context 'em sombra' do
      let(:mode) { 'sombra' }

      it 'nao altera a conversa e registra divergencia' do
        result = Rt::Routing::Resolve.call(conversation, legacy: 'humano')
        expect(result).to include(respondent: 'ia', applied: false)
        expect(conversation.reload.team_id).to be_nil
        expect(Rt::RoutingShadowLog.diverged.count).to eq(1)
      end

      it 'registra sem divergencia quando concorda' do
        Rt::Routing::Resolve.call(conversation, legacy: 'ia')
        expect(Rt::RoutingShadowLog.diverged.count).to eq(0)
        expect(Rt::RoutingShadowLog.count).to eq(1)
      end
    end

    context 'em legado' do
      let(:mode) { 'legado' }

      it 'nunca altera nada' do
        Rt::Routing::Resolve.call(conversation, legacy: 'ia')
        expect(conversation.reload.team_id).to be_nil
        expect(Rt::RoutingShadowLog.count).to eq(0)
      end
    end
  end

  describe 'F-3 assuncao e devolucao' do
    before { conversation.update!(team: ia_team) }

    def human_reply(content: 'oi', attrs: nil, private: false)
      Current.user = agent
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, private: private,
                       sender: agent, content: content, content_attributes: attrs)
    ensure
      Current.reset
    end

    it 'mensagem publica de humano numa fila de IA sem responsavel o torna responsavel' do
      human_reply
      expect(conversation.reload.assignee_id).to eq(agent.id)
      expect(Rt::RoutingEvent.where(reason: 'assuncao_humana').count).to eq(1)
      expect(Rt::Routing::Resolve.call(conversation)).to include(respondent: 'humano', reason: 'responsavel_humano')
    end

    it 'nota privada e mensagem da propria IA nao contam como assuncao' do
      human_reply(private: true)
      human_reply(attrs: { rt_origin: 'ia' })
      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'em modo legado nao marca assuncao' do
      Rt::InboxEntryQueue.find_by(inbox_id: inbox.id).update!(routing_mode: 'legado')
      human_reply
      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'devolver a IA = soltar o responsavel; a IA volta a responder' do
      human_reply
      conversation.update!(assignee_id: nil)
      expect(Rt::Routing::Resolve.call(conversation.reload)).to include(respondent: 'ia')
      expect(Rt::RoutingEvent.where(reason: 'devolucao_a_ia').count).to eq(1)
    end

    it 'humano -> IA -> humano -> IA pelo gesto de trocar a fila' do
      conversation.update!(team: humans, assignee: agent)
      expect(Rt::Routing::Resolve.call(conversation)[:respondent]).to eq('humano')
      conversation.update!(team: ia_team)
      expect(conversation.reload.assignee_id).to be_nil
      expect(Rt::Routing::Resolve.call(conversation)[:respondent]).to eq('ia')
      conversation.update!(team: humans)
      expect(Rt::Routing::Resolve.call(conversation)[:respondent]).to eq('humano')
    end
  end

  describe 'F-5 repasse' do
    before { conversation.update!(team: ia_team) }

    it 'aplica nota privada com o resumo e atribui a fila permitida' do
      result = Rt::Routing::Handoff.call(conversation: conversation, destination: 'humanos', summary: 'cliente quer 2a via', run_id: 'r1')
      expect(result.ok).to be(true)
      expect(conversation.reload.team_id).to eq(humans.id)
      note = conversation.messages.where(private: true).last
      expect(note.content).to include('cliente quer 2a via')
      expect(Rt::RoutingEvent.where(reason: 'repasse_da_ia', run_id: 'r1').count).to eq(1)
    end

    it 'sem destino explicito usa a fila de repasse padrao' do
      expect(Rt::Routing::Handoff.call(conversation: conversation).team_id).to eq(humans.id)
    end

    it 'destino nao permitido e ignorado e registrado' do
      result = Rt::Routing::Handoff.call(conversation: conversation, destination: fin_team.name, summary: 'x')
      expect(result.ok).to be(false)
      expect(conversation.reload.team_id).to eq(ia_team.id)
      expect(Rt::RoutingEvent.where(reason: 'recusado:destino_nao_permitido').count).to eq(1)
      expect(conversation.messages.where(private: true)).to be_empty
    end

    it 'fila sem destinos permitidos: a IA nao consegue repassar' do
      Rt::QueueBinding.find_by(team_id: ia_team.id).update!(allowed_destination_team_ids: [])
      expect(Rt::Routing::Handoff.call(conversation: conversation, destination: 'humanos').reason).to eq('sem_destinos_permitidos')
    end
  end

  describe 'F-6 contexto' do
    it 'historico completo inclui notas internas marcadas e papeis' do
      conversation.update!(team: ia_team)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'quero cancelar')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent, content: 'vou ver')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, private: true,
                       sender: agent, content: 'cliente VIP')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                       content: 'resposta da IA', content_attributes: { rt_origin: 'ia' })
      entries = Rt::Routing::History.call(conversation)
      expect(entries.pluck(:role)).to eq(%w[cliente atendente nota_interna ia])
      note = entries.find { |e| e[:role] == 'nota_interna' }
      expect(note).to include(internal: true, tag: Rt::Routing::History::INTERNAL_TAG, content: 'cliente VIP')
    end
  end

  describe 'rotas internas' do
    let(:headers) { { 'Authorization' => 'Bearer segredo' } }

    around { |example| with_modified_env(RT_INTERNAL_TOKEN: 'segredo') { example.run } }

    it 'exige o token de servico' do
      get '/internal/routing/resolve', params: { account_id: account.id, conversation_id: conversation.display_id }
      expect(response).to have_http_status(:unauthorized)
      get '/internal/routing/resolve', params: { account_id: account.id, conversation_id: conversation.display_id },
                                       headers: { 'Authorization' => 'Bearer errado' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'pending lista so conversa de IA cuja ultima mensagem e do cliente sem resposta' do
      conversation.update!(team: ia_team)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi?')
      get '/internal/routing/pending', params: { minutes: 15 }, headers: headers
      expect(response.parsed_body['items']).to include(include('conversation_id' => conversation.display_id, 'message' => include('content' => 'oi?')))
      Current.user = agent
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent, content: 'ola')
      Current.reset
      get '/internal/routing/pending', params: { minutes: 15 }, headers: headers
      expect(response.parsed_body['items'].pluck('conversation_id')).not_to include(conversation.display_id)
    end

    it 'resolve devolve quem responde' do
      get '/internal/routing/resolve', params: { account_id: account.id, conversation_id: conversation.display_id }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('respondent' => 'ia', 'agent' => 'tpl-1', 'routing_mode' => 'filas')
    end

    it '404 para conversa de outra conta' do
      other = create(:account)
      get '/internal/routing/resolve', params: { account_id: other.id, conversation_id: conversation.display_id }, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'lista destinos, aplica repasse e entrega historico' do
      conversation.update!(team: ia_team)
      get '/internal/routing/destinations', params: { account_id: account.id, conversation_id: conversation.display_id }, headers: headers
      expect(response.parsed_body['destinations'].first).to include('name' => 'humanos', 'description' => 'atendimento humano')

      post '/internal/routing/handoff', params: { account_id: account.id, conversation_id: conversation.display_id, queue: 'financeiro' },
                                        headers: headers
      expect(response).to have_http_status(:unprocessable_entity)

      post '/internal/routing/handoff', params: { account_id: account.id, conversation_id: conversation.display_id, queue: 'humanos',
                                                  summary: 'precisa de humano' }, headers: headers
      expect(response).to have_http_status(:ok)

      get '/internal/routing/history', params: { account_id: account.id, conversation_id: conversation.display_id }, headers: headers
      expect(response.parsed_body['messages'].last).to include('role' => 'nota_interna')
    end
  end
end
