# BFF de Agentes (spec 10, U-3a): lista, criação, rascunho, validação, versão e publicação.
# Cada ação exige a permissão `ai.agents.*` correspondente; o motor revalida e filtra por empresa.
class Api::V1::Accounts::RtAi::AgentsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i
  KINDS = %w[skills structured].freeze

  before_action -> { require_permission('ai.agents.view') }, only: [:index, :draft, :versions]
  before_action -> { require_permission('ai.agents.create') }, only: [:create]
  before_action -> { require_permission('ai.agents.edit') }, only: [:update_draft, :validate, :create_version]
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
    render_engine engine_put("/api/templates/#{params[:id]}/draft", package_params)
  end

  def validate
    render_engine engine_post("/api/templates/#{params[:id]}/validate", package_params)
  end

  def versions
    render_engine engine_get("/api/templates/#{params[:id]}/versions")
  end

  def create_version
    render_engine engine_post("/api/templates/#{params[:id]}/versions", { source: 'draft', notes: params[:notes].to_s })
  end

  def publish
    render_engine engine_post("/api/templates/#{params[:id]}/deploy", { version_id: params.require(:version_id) })
  end

  def destroy
    render_engine engine_delete("/api/templates/#{params[:id]}")
  end

  private

  def render_engine(data)
    render json: data unless performed?
  end

  def package_params
    { files: params.permit(files: [:path, :content])[:files].to_a.map(&:to_h),
      manifest: params[:manifest].respond_to?(:to_unsafe_h) ? params[:manifest].to_unsafe_h : {} }
  end

  def need_uuid
    head :not_found unless UUID.match?(params[:id].to_s)
  end
end
