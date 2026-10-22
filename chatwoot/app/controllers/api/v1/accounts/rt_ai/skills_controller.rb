# BFF de Skills (duas camadas), rotinas e propostas de memória (spec 10, U-3a / H-3).
# "Minhas" é só do usuário e o motor filtra por empresa e dono; "Da empresa" é compartilhada pelo
# tenant e só muda com `ai.skills.manage_company` ou `ai.agents.edit`.
class Api::V1::Accounts::RtAi::SkillsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i
  ACTIONS = %w[approve discard disable enable].freeze
  COMPANY_ACTIONS = %w[enable disable].freeze
  PASSTHROUGH_STATUSES = [400, 404, 409, 422].freeze
  COMPANY_MANAGE = %w[ai.skills.manage_company ai.agents.edit].freeze

  before_action -> { require_permission('ai.skills.view') }, only: [:index, :show, :company, :company_show, :company_files, :agent_skills]
  before_action -> { require_permission('ai.skills.manage_own') }, only: [:create, :update, :act, :destroy]
  before_action :require_company_manage, only: [:company_file_upload, :company_file_destroy, :agent_skills_update, :company_create, :company_update, :company_destroy, :company_act]
  before_action -> { require_permission('ai.routines.view') }, only: [:routines, :routine_runs]
  before_action -> { require_permission('ai.routines.manage') }, only: [:routine_create, :routine_update, :routine_act, :routine_destroy]
  before_action -> { require_permission('ai.memories.review') }, only: [:memory_proposals, :memory_act]
  before_action :need_uuid, only: [:show, :update, :act, :destroy, :company_show, :company_update, :company_destroy,
                                   :company_act, :routine_update, :routine_runs, :routine_act, :routine_destroy, :memory_act]

  # ---- Minhas
  def index
    render_engine engine_get('/api/me/skills')
  end

  def show
    render_engine engine_get("/api/me/skills/#{params[:id]}")
  end

  def create
    render_engine engine_post('/api/me/skills', { content: params[:content].to_s })
  end

  def update
    render_engine engine_put("/api/me/skills/#{params[:id]}", { content: params[:content].to_s })
  end

  def act
    return head :not_found unless ACTIONS.include?(params[:do])

    render_engine engine_post("/api/me/skills/#{params[:id]}/#{params[:do]}")
  end

  def destroy
    render_engine engine_delete("/api/me/skills/#{params[:id]}")
  end

  # ---- Arquivos da skill da empresa e vínculo agente <-> skills (spec 11 §4)
  def company_files
    return head :not_found unless params[:id].to_s.match?(UUID)

    render_engine engine_get("/api/skills/company/#{params[:id]}/files")
  end

  def company_file_upload
    return head :not_found unless params[:id].to_s.match?(UUID)

    render_engine engine_post("/api/skills/company/#{params[:id]}/files",
                              { name: params[:name].to_s, mime: params[:mime].to_s.presence,
                                content_b64: params[:content_b64].to_s })
  end

  def company_file_destroy
    return head :not_found unless params[:id].to_s.match?(UUID) && params[:file_id].to_s.match?(UUID)

    render_engine engine_delete("/api/skills/company/#{params[:id]}/files/#{params[:file_id]}")
  end

  def agent_skills
    return head :not_found unless params[:template_id].to_s.match?(UUID)

    render_engine engine_get("/api/skills/agent/#{params[:template_id]}")
  end

  def agent_skills_update
    return head :not_found unless params[:template_id].to_s.match?(UUID)

    render_engine engine_put("/api/skills/agent/#{params[:template_id]}",
                             { skill_ids: Array(params[:skill_ids]).map(&:to_s) })
  end

  # ---- Da empresa
  def company
    render_engine engine_get('/api/skills/company')
  end

  def company_show
    render_engine engine_get("/api/skills/company/#{params[:id]}")
  end

  def company_create
    render_engine engine_post('/api/skills/company', { content: params[:content].to_s })
  end

  def company_update
    render_engine engine_put("/api/skills/company/#{params[:id]}", { content: params[:content].to_s })
  end

  def company_destroy
    render_engine engine_delete("/api/skills/company/#{params[:id]}")
  end

  def company_act
    return head :not_found unless COMPANY_ACTIONS.include?(params[:do])

    render_engine engine_post("/api/skills/company/#{params[:id]}/#{params[:do]}")
  end

  # ---- Rotinas
  def routines
    render_engine engine_get('/api/schedules')
  end

  def routine_runs
    render_engine engine_get("/api/schedules/#{params[:id]}/runs")
  end

  def routine_create
    render_engine engine_post('/api/schedules', routine_params)
  end

  def routine_update
    render_engine engine_put("/api/schedules/#{params[:id]}", routine_params)
  end

  def routine_act
    return head :not_found unless %w[pause resume].include?(params[:do])

    render_engine engine_post("/api/schedules/#{params[:id]}/#{params[:do]}")
  end

  def routine_destroy
    render_engine engine_delete("/api/schedules/#{params[:id]}")
  end

  # ---- Memória
  def memory_proposals
    render_engine engine_get('/api/memories/proposals')
  end

  def memory_act
    return head :not_found unless %w[approve discard].include?(params[:do])

    render_engine engine_post("/api/memories/proposals/#{params[:id]}/#{params[:do]}")
  end

  private

  def require_company_manage
    return if COMPANY_MANAGE.intersect?(Current.account_user&.permissions || [])

    render json: { code: 'forbidden', message: 'Permissão negada' }, status: :forbidden
  end

  def routine_params
    params.permit(:name, :instruction, :cron, :timezone, :template_id, :active,
                  frequency: [:kind, :time, :minute, :day, { weekdays: [] }]).to_h
  end

  def render_engine(data)
    render json: data unless performed?
  end

  # Erro de validação do motor (nome repetido, segredo no texto, intervalo curto...) chega ao usuário
  # com a mensagem e os problemas dele; o resto (rede, 5xx, contexto recusado) segue como 502 genérico.
  def engine_failed(error)
    return super unless PASSTHROUGH_STATUSES.include?(error.status) && error.body.is_a?(Hash)

    problems = Array(error.body['problems'])
    message = problems.first&.dig('message') || error.body['detail'].to_s
    render json: { code: 'engine_rejected', message: message, problems: problems }, status: error.status
    nil
  end

  def need_uuid
    head :not_found unless UUID.match?(params[:id].to_s)
  end
end
