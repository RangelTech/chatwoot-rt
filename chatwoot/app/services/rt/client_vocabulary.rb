# Vocabulário visível ao cliente (spec 10): nomes técnicos de modelo, chave e produto nunca chegam à tela.
# Só apresentação: os dados do motor não mudam, o BFF traduz o que devolve.
module Rt
  module ClientVocabulary
    # Termos que nunca podem aparecer em texto de cliente (usado também pela varredura automatizada).
    FORBIDDEN_TERMS = %w[ninerouter litellm langgraph hermes harness kernel captain chatwoot ratende].freeze

    # Alias técnico -> nome amigável. O primeiro padrão que casar vence. Configurável por
    # RT_MODEL_ALIASES (JSON {"regex": "Nome"}), que tem prioridade sobre estes padrões.
    DEFAULT_MODEL_ALIASES = {
      'gpt|openai|o[134]-' => 'GPT',
      'sonnet|opus|haiku|claude|anthropic' => 'Claude',
      'gemini|google' => 'Gemini',
      'llama' => 'Llama',
      'qwen' => 'Qwen',
      'mistral' => 'Mistral',
      'deepseek' => 'DeepSeek'
    }.freeze
    MODEL_FALLBACK = 'Modelo padrão'.freeze

    PROVIDER_LABELS = {
      'openai' => 'OpenAI', 'anthropic' => 'Anthropic', 'google' => 'Google', 'gemini' => 'Google',
      'openrouter' => 'OpenRouter'
    }.freeze
    PROVIDER_FALLBACK = 'Padrão'.freeze

    # Ordem importa: o termo mais longo primeiro.
    TEXT_REPLACEMENTS = [
      [/Bridge\s+Chatwoot/i, 'Canal de mensagens'],
      [/Chatwoot/i, 'LUAR'],
      [/RAtende/i, 'LUAR'],
      [/ninerouter/i, 'modelo'],
      [/litellm|langgraph|hermes|harness|kernel|captain/i, 'LUAR']
    ].freeze

    module_function

    def model_aliases
      custom = begin
        JSON.parse(ENV.fetch('RT_MODEL_ALIASES', '{}'))
      rescue JSON::ParserError
        {}
      end
      custom.is_a?(Hash) ? custom.merge(DEFAULT_MODEL_ALIASES) { |_k, mine, _| mine } : DEFAULT_MODEL_ALIASES
    end

    def model_label(raw)
      name = raw.to_s
      model_aliases.each do |pattern, label|
        return label if name.match?(Regexp.new(pattern, Regexp::IGNORECASE))
      rescue RegexpError
        next
      end
      MODEL_FALLBACK
    end

    def provider_label(raw)
      PROVIDER_LABELS.fetch(raw.to_s.downcase, PROVIDER_FALLBACK)
    end

    def sanitize(text)
      TEXT_REPLACEMENTS.reduce(text.to_s) { |memo, (re, to)| memo.gsub(re, to) }
    end

    def forbidden?(text)
      FORBIDDEN_TERMS.any? { |term| text.to_s.downcase.include?(term) }
    end

    # Resposta de Uso: modelos e provedores com nomes de cliente, linhas iguais somadas.
    def usage(data)
      return data unless data.is_a?(Hash) && data['by_model'].is_a?(Array)

      merged = {}
      data['by_model'].each do |row|
        key = [provider_label(row['provider']), model_label(row['model'])]
        acc = (merged[key] ||= { 'provider' => key[0], 'model' => key[1], 'calls' => 0, 'tokens' => 0, 'cost_usd' => 0.0 })
        acc['calls'] += row['calls'].to_i
        acc['tokens'] += row['tokens'].to_i
        acc['cost_usd'] += row['cost_usd'].to_f
      end
      data.merge('by_model' => merged.values)
    end

    # Integrações: o nome da chave é texto livre do cadastro; só a apresentação é traduzida.
    def integrations(data)
      list = if data.is_a?(Array)
               data
             else
               data.is_a?(Hash) ? data['items'] : nil
             end
      return data unless list.is_a?(Array)

      cleaned = list.map { |item| item.is_a?(Hash) && item['name'] ? item.merge('name' => sanitize(item['name'])) : item }
      data.is_a?(Array) ? cleaned : data.merge('items' => cleaned)
    end

    def present(key, data)
      case key
      when 'usage' then usage(data)
      when 'integrations' then integrations(data)
      else data
      end
    end
  end
end
