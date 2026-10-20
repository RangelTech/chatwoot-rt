require 'rails_helper'

# Varredura automatizada (spec 10, rodada 2): nada de nome interno em texto visível ao cliente.
RSpec.describe Rt::ClientVocabulary, 'sweep' do
  let(:terms) { Rt::ClientVocabulary::FORBIDDEN_TERMS }

  def strings_in(node, path = [])
    case node
    when Hash then node.flat_map { |k, v| strings_in(v, path + [k]) }
    when Array then node.each_with_index.flat_map { |v, i| strings_in(v, path + [i]) }
    when String then [[path.join('.'), node]]
    else []
    end
  end

  %w[pt_BR en].each do |locale|
    it "has no internal names in the #{locale} ragent.json locale" do
      file = Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/ragent.json")
      offenders = strings_in(JSON.parse(File.read(file))).select { |_p, text| terms.any? { |t| text.downcase.include?(t) } }
      expect(offenders).to be_empty, offenders.map { |p, t| "#{p}: #{t}" }.join("\n")
    end
  end

  it 'has no internal names in the legal pages' do
    Dir[Rails.root.join('app/views/legal/*.erb')].each do |file|
      text = File.read(file).gsub(%r{<style.*?</style>}m, '').gsub(/<[^>]+>/, ' ').downcase
      hits = terms.select { |t| text.include?(t) }
      expect(hits).to be_empty, "#{File.basename(file)}: #{hits.join(', ')}"
    end
  end

  it 'has no internal names in the usage and integrations BFF responses' do
    usage = { 'by_model' => [{ 'provider' => 'ninerouter', 'model' => 'ninerouter-sonnet', 'calls' => 1, 'tokens' => 1, 'cost_usd' => 0 }] }
    integrations = [{ 'name' => 'Bridge Chatwoot (regravado 21/08)' }, { 'name' => 'Kernel RAtende' }]
    rendered = [Rt::ClientVocabulary.present('usage', usage), Rt::ClientVocabulary.present('integrations', integrations)].to_json.downcase
    expect(terms.select { |t| rendered.include?(t) }).to be_empty
  end
end
