require 'rails_helper'

RSpec.describe Rt::ClientVocabulary do
  it 'maps technical model aliases to friendly names with a generic fallback' do
    expect(described_class.model_label('ninerouter-gpt')).to eq('GPT')
    expect(described_class.model_label('ninerouter-sonnet')).to eq('Claude')
    expect(described_class.model_label('tenant_x_combo_principal')).to eq('Modelo padrão')
    expect(described_class.model_label(nil)).to eq('Modelo padrão')
  end

  it 'lets RT_MODEL_ALIASES add or override aliases' do
    with_modified_env(RT_MODEL_ALIASES: '{"combo_principal":"Principal","gpt":"Modelo A"}') do
      expect(described_class.model_label('tenant_x_combo_principal')).to eq('Principal')
      expect(described_class.model_label('ninerouter-gpt')).to eq('Modelo A')
    end
  end

  it 'ignores broken RT_MODEL_ALIASES' do
    with_modified_env(RT_MODEL_ALIASES: '{nope') do
      expect(described_class.model_label('ninerouter-gpt')).to eq('GPT')
    end
  end

  it 'merges usage rows that share the same friendly name' do
    data = { 'totals' => { 'calls' => 3 },
             'by_model' => [
               { 'provider' => 'ninerouter', 'model' => 'ninerouter-gpt', 'calls' => 2, 'tokens' => 10, 'cost_usd' => 0.1 },
               { 'provider' => 'ninerouter', 'model' => 'ninerouter-gpt-mini', 'calls' => 1, 'tokens' => 5, 'cost_usd' => 0.05 }
             ] }
    rows = described_class.usage(data)['by_model']
    expect(rows.size).to eq(1)
    expect(rows.first).to include('model' => 'GPT', 'provider' => 'Padrão', 'calls' => 3, 'tokens' => 15)
    expect(rows.first['cost_usd']).to be_within(0.0001).of(0.15)
  end

  it 'rewrites technical product names in integration key names without touching the rest' do
    data = [{ 'id' => 1, 'name' => 'Bridge Chatwoot (regravado 21/08)', 'key_prefix' => 'abc' }]
    out = described_class.integrations(data)
    expect(out.first['name']).to eq('Canal de mensagens (regravado 21/08)')
    expect(out.first['key_prefix']).to eq('abc')
  end

  it 'passes unknown shapes through' do
    expect(described_class.usage('x' => 1)).to eq('x' => 1)
    expect(described_class.present('providers', [1])).to eq([1])
  end
end
