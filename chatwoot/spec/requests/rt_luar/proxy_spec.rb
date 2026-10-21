require 'rails_helper'

RSpec.describe 'RtLuar::Proxy', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:base) { "/rt_luar/api/v1/accounts/#{account.id}" }

  around do |example|
    with_modified_env(RT_UI_CONTEXT_SECRET: 'segredo') { example.run }
  end

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    Rt::AiAccount.create!(account: account, ai_state: 'active', flags: { 'ai_enabled' => true })
  end

  def ctx(user: agent, account_id: account.id, run_id: 'run-1', ttl: 900)
    Rt::LuarContext.mint(account_id: account_id, user_id: user.id, run_id: run_id, ttl: ttl)
  end

  def luar(verb, path, token: ctx, **)
    send(verb, "#{base}/#{path}", headers: { 'X-Luar-Context' => token }, as: :json, **)
  end

  describe 'autenticação do contexto' do
    it 'rejeita ausente ou malformado' do
      get "#{base}/conversations"
      expect(response).to have_http_status(:unauthorized)
      luar(:get, 'conversations', token: 'lixo.lixo')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita assinatura adulterada' do
      body, = ctx.split('.')
      luar(:get, 'conversations', token: "#{body}.#{Base64.urlsafe_encode64('x')}")
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita expirado' do
      token = ctx
      travel_to(16.minutes.from_now) { luar(:get, 'conversations', token: token) }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita aud errada' do
      token = Rt::EngineClient.sign(aud: 'ui', account_id: account.id, user_id: agent.id, run_id: 'r', exp: 5.minutes.from_now.to_i)
      luar(:get, 'conversations', token: token)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'limita o TTL a 15 minutos' do
      token = Rt::EngineClient.sign(aud: 'luar', account_id: account.id, user_id: agent.id, run_id: 'r', exp: 2.hours.from_now.to_i)
      luar(:get, 'conversations', token: token)
      expect(response).to have_http_status(:unauthorized)
      expect(Rt::LuarContext.verify(ctx(ttl: 99_999))['exp'] - Time.now.to_i).to be <= 900
    end

    it 'permite reutilizar o mesmo contexto' do
      token = ctx
      2.times do
        luar(:get, 'conversations', token: token)
        expect(response).to have_http_status(:success), response.body
      end
    end
  end

  describe 'conta e membership' do
    it 'bloqueia conta do caminho diferente da do contexto' do
      other = create(:account)
      luar(:get, 'conversations', token: ctx(account_id: other.id))
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('luar_blocked')
    end

    it 'bloqueia usuário que não é membro' do
      stranger = create(:user)
      luar(:get, 'conversations', token: ctx(user: stranger))
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'permissões normais do Chatwoot' do
    it 'agente lê conversas do inbox em que é membro' do
      conversation
      luar(:get, 'conversations')
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('data', 'payload').pluck('id')).to include(conversation.display_id)
    end

    it 'agente sem acesso ao inbox não vê a conversa' do
      other = create(:conversation, account: account, inbox: create(:inbox, account: account))
      luar(:get, "conversations/#{other.display_id}")
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden).or have_http_status(:not_found)
      luar(:get, 'conversations')
      expect(response.parsed_body).to be_a(Hash), response.body
      expect(response.parsed_body.dig('data', 'payload').pluck('id')).not_to include(other.display_id)
    end

    it 'muda o status da conversa' do
      luar(:post, "conversations/#{conversation.display_id}/toggle_status", params: { status: 'resolved' })
      expect(response).to have_http_status(:success)
      expect(conversation.reload.status).to eq('resolved')
    end

    it 'preserva a query string' do
      conversation
      luar(:get, 'conversations?status=resolved')
      expect(response.parsed_body.dig('data', 'payload')).to be_empty
    end
  end

  describe 'bloqueios' do
    it 'bloqueia gestão de usuários, perfis e tokens' do
      %w[agents account_users custom_roles rt_ai/members agent_bots/1/reset_access_token].each do |path|
        luar(:get, path, token: ctx(user: admin))
        expect(response).to have_http_status(:forbidden), path
        expect(response.parsed_body['code']).to eq('luar_blocked')
      end
    end

    it 'bloqueia travessia de caminho' do
      luar(:get, 'conversations/../agents', token: ctx(user: admin))
      expect(response).to have_http_status(:forbidden)
      luar(:get, 'conversations/%2e%2e/agents', token: ctx(user: admin))
      expect(response).to have_http_status(:forbidden)
    end

    it 'bloqueia DELETE de inbox e da conta' do
      luar(:delete, "inboxes/#{inbox.id}", token: ctx(user: admin))
      expect(response).to have_http_status(:forbidden)
      delete base, headers: { 'X-Luar-Context' => ctx(user: admin) }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Inbox.exists?(inbox.id)).to be(true)
    end

    it 'bloqueia mensagem outgoing sem outbound_enabled' do
      luar(:post, "conversations/#{conversation.display_id}/messages", params: { content: 'oi', private: false })
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('luar_blocked')
      luar(:post, "conversations/#{conversation.display_id}/messages", params: { content: 'oi' })
      expect(response).to have_http_status(:forbidden)
      luar(:post, "conversations/#{conversation.display_id}/transcript", params: { email: 'x@y.com' })
      expect(response).to have_http_status(:forbidden)
    end

    it 'permite nota privada' do
      luar(:post, "conversations/#{conversation.display_id}/messages", params: { content: 'nota', private: true })
      expect(response).to have_http_status(:success)
      expect(conversation.messages.last).to have_attributes(private: true, content: 'nota')
    end

    it 'permite outgoing com a flag ligada' do
      Rt::AiAccount.first.update!(flags: { 'outbound_enabled' => true })
      luar(:post, "conversations/#{conversation.display_id}/messages", params: { content: 'oi' })
      expect(response).to have_http_status(:success)
    end
  end

  describe 'auditoria e rate limit' do
    it 'grava auditoria sem query nem corpo' do
      luar(:post, "conversations/#{conversation.display_id}/messages", params: { content: 'segredo', private: true })
      audit = Rt::LuarAudit.last
      expect(audit).to have_attributes(account_id: account.id, user_id: agent.id, run_id: 'run-1', http_method: 'POST', status: 200)
      expect(audit.path).to eq("/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages")
      expect(audit.attributes.values.join).not_to include('segredo')
    end

    it 'audita também as negações' do
      luar(:get, 'agents', token: ctx(user: admin))
      expect(Rt::LuarAudit.last).to have_attributes(status: 403, path: "/api/v1/accounts/#{account.id}/agents")
    end

    it 'aplica 120 req/min por usuário' do
      allow(Rack::Attack.cache).to receive(:count).and_return(121)
      luar(:get, 'conversations')
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
