require 'rails_helper'

RSpec.describe Rt::AiRoles do
  let(:account) { create(:account) }

  it 'gives administrators the full AI profile and keeps the native role string' do
    admin = create(:account_user, account: account, role: :administrator)
    expect(admin.permissions).to include('administrator', 'ai.environment.manage', 'ai.members.manage_roles')
  end

  it 'gives agents the operator profile only' do
    agent = create(:account_user, account: account, role: :agent)
    expect(agent.permissions).to include('agent', 'ai.chat.run')
    expect(agent.permissions).not_to include('ai.environment.manage', 'ai.credentials.manage', 'ai.agents.edit')
  end

  it 'applies a stored grant over the default profile' do
    agent = create(:account_user, account: account, role: :agent)
    Rt::AiGrant.create!(account_user: agent, role_key: 'leitor')
    expect(agent.reload.permissions).to include('ai.chat.view')
    expect(agent.permissions).not_to include('ai.chat.run')
  end

  it 'rejects unknown profiles' do
    agent = create(:account_user, account: account, role: :agent)
    expect(Rt::AiGrant.new(account_user: agent, role_key: 'root')).not_to be_valid
  end

  it 'never grants manager the secrets, environment or role management' do
    expect(described_class::GESTOR).not_to include('ai.credentials.manage', 'ai.environment.manage', 'ai.members.manage_roles')
  end
end
