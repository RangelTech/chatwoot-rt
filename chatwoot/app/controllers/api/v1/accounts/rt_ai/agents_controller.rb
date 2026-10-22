# BFF de Agentes (spec 10, U-3a): lista, criação, rascunho, validação, versão e publicação.
# Cada ação exige a permissão `ai.agents.*` correspondente; o motor revalida e filtra por empresa.
class Api::V1::Accounts::RtAi::AgentsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i
  # Arquivos do pacote (qualquer tipo) ficam na pasta reservada `arquivos/`; o motor revalida tudo.
  ASSETS_DIR = 'arquivos'.freeze
  MAX_ASSET_BYTES = 10 * 1024 * 1024
  ASSET_PATH = %r{\Aarquivos/[^\\\x00-\x1f]{1,200}\z}
  KINDS = %w[skills structured].freeze

  before_action -> { require_permission('ai.agents.view') }, only: [:index, :draft, :versions]
  before_action -> { require_permission('ai.agents.create') }, only: [:create]
  before_action -> { require_permission('ai.agents.edit') }, only: [:update_draft, :validate, :create_version, :upload_file, :delete_file]
  before_action -> { require_permission('ai.agents.publish') }, only: [:publish]
  before_action -> { require_permission('ai.agents.archive') }, only: [:destroy]
  before_action :need_uuid, except: [:index, :create]

  def index
    render_engine engine_get('/api/templates')
  end

  def create
    body = params.permit(:name, :description, :agent_kind).to_h
    body['agent_kind'] = 'skills' unless KINDS.include?(body['agent_kind'])
    render_engine engine_post('/api/templates', body)
  end

  def draft
    render_engine engine_get("/api/templates/#{params[:id]}/draft")
  end

  def update_draft
    package = package_params
    return unless combo_allowed!(package[:manifest])

    render_engine engine_put("/api/templates/#{params[:id]}/draft", package)
  end

  def validate
    package = package_params
    return unless combo_allowed!(package[:manifest])

    render_engine engine_post("/api/templates/#{params[:id]}/validate", package)
  end

  # Envia ou substitui um arquivo do pacote (multipart: `file`, `path` opcional).
  def upload_file
    file = params[:file]
    return render_file_error('invalid_file', 'Selecione um arquivo.') unless file.respond_to?(:read)
    return render_file_error('file_too_large', 'O arquivo passa de 10 MB.') if file.size > MAX_ASSET_BYTES

    path = asset_path(params[:path].presence || file.original_filename)
    return render_file_error('invalid_file', 'Nome de arquivo inválido.') unless path

    body = { content_base64: Base64.strict_encode64(file.read) }
    render json: Rt::EngineClient.put("/api/templates/#{params[:id]}/draft/files/#{encode_path(path)}", body, claims: engine_context)
  rescue Rt::EngineClient::Error => e
    engine_file_failed(e)
  end

  def delete_file
    path = params[:path].to_s
    return render_file_error('invalid_file', 'Nome de arquivo inválido.') unless ASSET_PATH.match?(path) && path.split('/').none? { |p| ['', '.', '..'].include?(p) }

    render json: Rt::EngineClient.delete("/api/templates/#{params[:id]}/draft/files/#{encode_path(path)}", claims: engine_context)
  rescue Rt::EngineClient::Error => e
    engine_file_failed(e)
  end

  def versions
    render_engine engine_get("/api/templates/#{params[:id]}/versions")
  end

  def create_version
    # Re-read the persisted draft immediately before versioning. This makes a
    # forged/stale browser request unable to publish a combo from another
    # tenant, even if it skipped the client-side selector.
    draft = engine_get("/api/templates/#{params[:id]}/draft")
    return if performed? || !combo_allowed!(draft.is_a?(Hash) ? draft['manifest'] : nil)

    render_engine engine_post("/api/templates/#{params[:id]}/versions", { source: 'draft', notes: params[:notes].to_s })
  end

  def publish
    version_id = params.require(:version_id)
    version = engine_get("/api/templates/#{params[:id]}/versions/#{version_id}")
    return if performed? || !combo_allowed!(version.is_a?(Hash) ? version['manifest'] : nil)

    render_engine engine_post("/api/templates/#{params[:id]}/deploy", { version_id: version_id })
  end

  def destroy
    render_engine engine_delete("/api/templates/#{params[:id]}")
  end

  private

  def render_engine(data)
    render json: data unless performed?
  end

  # Sem pasta informada, o arquivo cai em arquivos/<nome>; só o nome base é aproveitado.
  def asset_path(raw)
    raw = raw.to_s.tr('\\', '/')
    raw = "#{ASSETS_DIR}/#{File.basename(raw)}" unless raw.start_with?("#{ASSETS_DIR}/")
    return nil unless ASSET_PATH.match?(raw) && raw.split('/').none? { |p| ['', '.', '..'].include?(p) || p.start_with?('.') }

    raw
  end

  def encode_path(path)
    path.split('/').map { |s| ERB::Util.url_encode(s) }.join('/')
  end

  def render_file_error(code, message, problems = [])
    render json: { code: code, message: message, problems: problems }, status: :unprocessable_entity
  end

  # Erro de validação do motor (formato, tamanho, segredo...) vai ao usuário com a mensagem dele.
  def engine_file_failed(error)
    problems = error.body.is_a?(Hash) ? Array(error.body['problems']) : []
    return render_file_error('invalid_file', problems.first&.dig('message') || error.body['detail'].to_s, problems) if error.status == 422 && error.body.is_a?(Hash)

    engine_failed(error)
  end

  def package_params
    { files: params.permit(files: [:path, :content])[:files].to_a.map(&:to_h),
      manifest: params[:manifest].respond_to?(:to_unsafe_h) ? params[:manifest].to_unsafe_h : {} }
  end

  # Combo ownership is checked through the authenticated account's Gateway
  # mapping. Never accept a tenant id from the browser or from the manifest.
  def combo_allowed!(manifest)
    model = manifest.is_a?(Hash) ? (manifest['model'] || manifest[:model]) : nil
    combo = model.is_a?(Hash) ? (model['combo'] || model[:combo]).to_s.strip : ''
    return true if combo.blank?

    response = Rt::GatewayClient.get(account: Current.account, path: '/api/combos')
    combos = response.is_a?(Hash) ? Array(response['combos']) : []
    return true if combos.any? { |item| item.is_a?(Hash) && item['name'].to_s == combo }

    render json: { code: 'invalid_combo', message: 'O combo selecionado não pertence a esta empresa.' }, status: :unprocessable_entity
    false
  rescue Rt::GatewayClient::Error => e
    Rails.logger.warn("rt_ai gateway combo validation error: #{e.message}")
    render json: { code: 'gateway_error', message: 'Não foi possível validar o combo de IA.' }, status: :bad_gateway
    false
  end

  def need_uuid
    head :not_found unless UUID.match?(params[:id].to_s)
  end
end
