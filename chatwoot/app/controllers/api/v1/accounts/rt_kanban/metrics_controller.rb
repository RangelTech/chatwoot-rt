# Métricas do quadro da Account (admin): contadores de movimento por resultado, latência, revisão e reconciliação.
class Api::V1::Accounts::RtKanban::MetricsController < Api::V1::Accounts::RtKanban::BaseController
  before_action :need_admin

  def show
    render json: RtKanban::Metrics.snapshot(Current.account)
  end
end
