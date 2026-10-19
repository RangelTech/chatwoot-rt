# BFF de Skills do usuário (aprendidas), rotinas e propostas de memória (spec 10, U-3a).
# Tudo é do próprio usuário; o motor filtra por empresa e dono.
class Api::V1::Accounts::RtAi::SkillsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i
  ACTIONS = %w[approve discard disable enable].freeze

  before_action -> { require_permission('ai.skills.view') }, only: [:index]
  before_action -> { require_permission('ai.skills.manage_own') }, only: [:act, :destroy]
  before_action -> { require_permission('ai.routines.view') }, only: [:routines]
  before_action -> { require_permission('ai.routines.manage') }, only: [:routine_act, :routine_destroy]
  before_action -> { require_permission('ai.memories.review') }, only: [:memory_proposals, :memory_act]
  before_action :need_uuid, only: [:act, :destroy, :routine_act, :routine_destroy, :memory_act]

  def index
    render_engine engine_get('/api/me/skills')
  end

  def act
    return head :not_found unless ACTIONS.include?(params[:do])

    render_engine engine_post("/api/me/skills/#{params[:id]}/#{params[:do]}")
  end

  def destroy
    render_engine engine_delete("/api/me/skills/#{params[:id]}")
  end

  def routines
    render_engine engine_get('/api/schedules')
  end

  def routine_act
    return head :not_found unless %w[pause resume].include?(params[:do])

    render_engine engine_post("/api/schedules/#{params[:id]}/#{params[:do]}")
  end

  def routine_destroy
    render_engine engine_delete("/api/schedules/#{params[:id]}")
  end

  def memory_proposals
    render_engine engine_get('/api/memories/proposals')
  end

  def memory_act
    return head :not_found unless %w[approve discard].include?(params[:do])

    render_engine engine_post("/api/memories/proposals/#{params[:id]}/#{params[:do]}")
  end

  private

  def render_engine(data)
    render json: data unless performed?
  end

  def need_uuid
    head :not_found unless UUID.match?(params[:id].to_s)
  end
end
