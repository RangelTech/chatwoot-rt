require 'rails_helper'

RSpec.describe Rt::AiAccount do
  it 'nasce com os agentes graph desligados (Fase L)' do
    expect(described_class::DEFAULT_FLAGS['graph_enabled']).to be(false)
    ai = described_class.new(flags: {})
    expect(ai.effective_flags['graph_enabled']).to be(false)
  end

  it 'a flag explicita da conta ainda prevalece sobre o padrao' do
    ai = described_class.new(flags: { 'graph_enabled' => true })
    expect(ai.effective_flags['graph_enabled']).to be(true)
  end
end
