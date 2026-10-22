# BFF da tela Credenciais (spec 10 §15.1): uma lista e um formulário por TIPO para tudo que o agente usa
# (segredo/API key, banco de dados, SSH, service account GCP, e-mail, pagamento e contas Google/Outlook).
# Cada tipo mapeia para uma rota do motor por allowlist: nada de caminho ou método vindos do navegador.
# Valores são write-only: a resposta é montada campo a campo e nunca carrega senha, chave ou token.
class Api::V1::Accounts::RtAi::CredentialsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i
  DB_KINDS = { 'postgres' => 'postgresql', 'mysql' => 'mysql', 'mongo' => 'mongodb', 'sqlite' => 'sqlite' }.freeze
  OAUTH = %w[google microsoft].freeze

  # Campos aceitos por tipo; o motor revalida (formato, tamanho, tenant).
  TYPES = {
    'secret' => { list: '/api/secrets', fields: %i[name value] },
    'ssh' => { list: '/api/secrets', fields: %i[name value host port user] },
    'gcp' => { list: '/api/secrets', fields: %i[name value] },
    'aws' => { list: '/api/secrets', fields: %i[name value] },
    'azure' => { list: '/api/secrets', fields: %i[name value] },
    'database' => { list: '/api/datasources', fields: %i[name db_kind host port database user password ssl path] },
    'email' => { list: '/api/email-accounts',
                 fields: %i[label email_address smtp_host smtp_port imap_host imap_port username password use_tls] },
    'payment' => { list: '/api/payments/credentials', fields: %i[access_token webhook_secret sandbox] },
    'google' => { list: '/api/google-accounts', fields: [] },
    'microsoft' => { list: '/api/microsoft-accounts', fields: [] }
  }.freeze

  # Tipos que moram na tabela de segredos do motor, distinguidos pelo campo `kind`.
  SECRET_KINDS = %w[secret ssh gcp aws azure].freeze
  # Uma consulta por origem no motor (segredo/SSH/GCP dividem a mesma).
  LISTS = TYPES.values.pluck(:list).uniq.freeze
  LIST_TYPE = TYPES.to_h { |type, cfg| [cfg[:list], type] }.freeze

  before_action -> { require_permission('ai.credentials.view') }, only: [:index]
  before_action -> { require_permission('ai.credentials.manage') }, only: [:create, :update, :destroy, :oauth_start, :test]
  before_action :find_type, only: [:create, :update, :destroy, :test]
  before_action :reject_connected_types, only: [:create, :update]
  before_action :need_id, only: [:update, :destroy, :test]

  def index
    items = []
    failures = 0
    LISTS.each do |path|
      rows = Rt::EngineClient.get(path, claims: engine_context)
      rows = [rows] if rows.is_a?(Hash)
      items.concat(Array(rows).filter_map { |row| present(LIST_TYPE[path], row) })
    rescue Rt::EngineClient::Error => e
      failures += 1
      Rails.logger.warn("rt_ai credentials list #{path}: #{e.message}")
    end
    return engine_failed(Rt::EngineClient::Error.new('all lists failed', status: 502)) if failures == LISTS.size

    render json: { items: items.sort_by { |i| [i[:type], i[:name].to_s.downcase] } }
  end

  def create
    render_saved engine_save(:post)
  end

  def update
    render_saved engine_save(:put, params[:id])
  end

  # Spec 11 §7: "Testar" roda no motor (nunca no navegador); só tipos guardados como segredo.
  def test
    return render json: { ok: true, detail: 'Este tipo não tem teste de conexão.' } unless SECRET_KINDS.include?(@rt_type)

    render json: Rt::EngineClient.post("/api/secrets/#{params[:id]}/test", {}, claims: engine_context)
  rescue Rt::EngineClient::Error => e
    engine_failed(e)
  end

  def destroy
    path = @rt_type == 'payment' ? "/api/payments/credentials/#{params[:id]}" : "#{TYPES[@rt_type][:list]}/#{params[:id]}"
    # DELETE do motor devolve 204 sem corpo em alguns tipos; o cliente só precisa saber que deu certo.
    Rt::EngineClient.delete(path, claims: engine_context)
    render json: { status: 'ok' }
  rescue JSON::ParserError
    render json: { status: 'ok' }
  rescue Rt::EngineClient::Error => e
    engine_failed(e)
  end

  # Devolve a URL de autorização do provedor; a conexão é concluída pelo motor quando o provedor volta.
  def oauth_start
    return head :not_found unless OAUTH.include?(params[:provider])

    body = { label: params[:label].to_s.strip.first(120).presence }.compact
    data = engine_post("/api/credentials/oauth/#{params[:provider]}/iniciar", body)
    render json: { auth_url: data['auth_url'] } if data && !performed?
  end

  private

  def find_type
    @rt_type = params[:type].to_s
    head :not_found unless TYPES.key?(@rt_type)
  end

  # Google e Outlook são conectados (OAuth), não cadastrados por formulário.
  def reject_connected_types
    return unless OAUTH.include?(@rt_type)

    render json: { code: 'not_supported', message: 'Este tipo é conectado, não cadastrado.' }, status: :unprocessable_entity
  end

  def need_id
    head :not_found unless UUID.match?(params[:id].to_s)
  end

  # A resposta passa pelo mesmo filtro da lista: o motor nunca devolve valores, mas o BFF não depende disso.
  def render_saved(data)
    return if performed?

    render json: present(@rt_type, data) || { status: 'ok' }
  end

  # Cria (POST) ou substitui (PUT). Campos vazios não são enviados: em "Substituir", vazio = manter.
  def engine_save(verb, id = nil)
    # Texto em branco = "manter"; booleanos `false` precisam seguir (ex.: desligar SSL ou o modo de teste).
    given = params.permit(*TYPES[@rt_type][:fields]).to_h.reject { |_, v| v.nil? || (v.is_a?(String) && v.blank?) }
    path, body = build_body(given, id)
    return nil if performed?

    # Pagamento é uma credencial por empresa: criar e substituir são o mesmo PUT do motor.
    verb == :post && @rt_type != 'payment' ? engine_post(path, body) : engine_put(path, body)
  end

  def build_body(given, id)
    case @rt_type
    when 'secret', 'gcp' then secret_body(@rt_type, given, id)
    when 'ssh' then secret_body('ssh', given, id, meta: given.slice('host', 'port', 'user'))
    when 'database' then build_database(given, id)
    when 'email' then build_email(given, id)
    else build_payment(given)
    end
  end

  # Segredo, SSH e GCP: tudo na tabela de segredos do motor. No PUT só valor e metadados mudam.
  def secret_body(kind, given, id, meta: nil)
    if id
      body = {}
      body['value'] = given['value'] if given['value']
      body['meta'] = meta if meta.present?
      ["/api/secrets/#{id}", body]
    else
      body = { 'name' => given['name'], 'value' => given['value'], 'kind' => kind }
      body['meta'] = meta if meta
      ['/api/secrets', body]
    end
  end

  # Banco de dados vira fonte de dados do motor: o que não é segredo vai em `config`, a senha em `secret`.
  def build_database(given, id)
    kind = DB_KINDS[given['db_kind']]
    config = database_config(given)
    if id
      body = {}
      body['config'] = config if config.present?
      body['secret'] = given['password'] if given['password']
      return ["/api/datasources/#{id}", body]
    end
    return render_invalid('Escolha o tipo de banco.') if kind.nil?

    ['/api/datasources', { 'name' => given['name'], 'kind' => kind, 'config' => config, 'secret' => given['password'] }.compact]
  end

  def database_config(given)
    config = given.slice('host', 'database', 'user', 'path').to_h
    config['port'] = given['port'].to_i if given['port']
    config['ssl'] = ActiveModel::Type::Boolean.new.cast(given['ssl']) if given.key?('ssl')
    config
  end

  def build_email(given, id)
    body = given.to_h
    %w[smtp_port imap_port].each { |k| body[k] = body[k].to_i if body[k] }
    body['use_tls'] = ActiveModel::Type::Boolean.new.cast(body['use_tls']) if body.key?('use_tls')
    [id ? "/api/email-accounts/#{id}" : '/api/email-accounts', body]
  end

  def build_payment(given)
    body = given.to_h
    body['sandbox'] = ActiveModel::Type::Boolean.new.cast(body['sandbox']) if body.key?('sandbox')
    ['/api/payments/credentials', body]
  end

  def render_invalid(message)
    render json: { code: 'invalid', message: message }, status: :unprocessable_entity
    nil
  end

  # Allowlist de saída por tipo. Nada de valor, chave, token ou senha: só o que a tela precisa mostrar.
  def present(type, row)
    return nil unless row.is_a?(Hash) && row['id']

    base = { id: row['id'], type: type, env_vars: Array(row['env_vars']).map(&:to_s),
             created_at: row['created_at'], updated_at: row['updated_at'], active: row['is_active'] != false }
    return present_secret(base, row) if SECRET_KINDS.include?(type)
    return present_database(base, row) if type == 'database'

    present_other(type, base, row)
  end

  def present_other(type, base, row)
    case type
    when 'email'
      base.merge(name: row['label'], info: row.slice('email_address', 'smtp_host', 'smtp_port', 'imap_host', 'imap_port', 'username', 'use_tls'))
    when 'payment'
      base.merge(name: 'Mercado Pago', info: { sandbox: row['sandbox'], has_token: row['has_token'], has_webhook_secret: row['has_webhook_secret'] })
    else
      base.merge(name: row['label'].presence || row['email_address'], info: { email_address: row['email_address'] })
    end
  end

  def present_secret(base, row)
    kind = SECRET_KINDS.include?(row['kind']) ? row['kind'] : 'secret'
    base.merge(type: kind, name: row['name'], info: { hint: row['hint'], last_test_ok: row['last_test_ok'], last_test_detail: row['last_test_detail'] }.merge((row['meta'] || {}).slice('host', 'port', 'user')))
  end

  def present_database(base, row)
    cfg = row['config'].is_a?(Hash) ? row['config'] : {}
    db_kind = DB_KINDS.key(row['kind']) || row['kind']
    info = cfg.slice('host', 'port', 'database', 'user', 'ssl', 'path').merge('db_kind' => db_kind, 'has_password' => row['has_secret'])
    base.merge(name: row['name'], info: info)
  end
end
