# BFF dos computadores conectados (spec 11 §26): proxy fino para o motor, que guarda as chaves
# e fala com o hub. Ver e testar com `ai.environment.view`; adicionar, renomear e remover com
# `ai.environment.manage`.
class Api::V1::Accounts::RtAi::HostsController < Api::V1::Accounts::RtAi::BaseController
  UUID = /\A[0-9a-f-]{36}\z/i

  before_action -> { require_permission('ai.environment.view') }, only: [:index, :test, :agent]
  before_action -> { require_permission('ai.environment.manage') }, only: [:create, :new_code, :update, :destroy, :agent_update]
  before_action :need_uuid, only: [:new_code, :update, :destroy, :test, :agent, :agent_update]

  def index
    render_engine engine_get('/api/hosts')
  end

  def create
    render_engine engine_post('/api/hosts', { name: params[:name].to_s })
  end

  def new_code
    render_engine engine_post("/api/hosts/#{params[:id]}/pair")
  end

  def update
    render_engine engine_put("/api/hosts/#{params[:id]}", { name: params[:name].to_s })
  end

  def destroy
    render_engine engine_delete("/api/hosts/#{params[:id]}")
  end

  def test
    render_engine engine_post("/api/hosts/#{params[:id]}/test")
  end

  def agent
    render_engine engine_get("/api/hosts/agent/#{params[:id]}")
  end

  def agent_update
    render_engine engine_put("/api/hosts/agent/#{params[:id]}", { host_ids: Array(params[:host_ids]).map(&:to_s) })
  end

  private

  def need_uuid
    head :not_found unless params[:id].to_s.match?(UUID)
  end

  def render_engine(data)
    render json: data unless performed?
  end
end
