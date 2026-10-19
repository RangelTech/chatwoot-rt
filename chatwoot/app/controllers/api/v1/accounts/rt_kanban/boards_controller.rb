class Api::V1::Accounts::RtKanban::BoardsController < Api::V1::Accounts::RtKanban::BaseController
  before_action :need_admin, only: [:update]

  def show
    counts = RtKanban::Card.where(board_id: @board.id).joins(:conversation).merge(visible).group(:stage_id).count
    render json: { id: @board.id, account_id: @board.account_id, revision: @board.revision, enabled: @board.enabled,
                   stages: @board.stages.map { |s| stage_json(s, counts[s.id].to_i) } }
  end

  # Liga/desliga o quadro da Account (admin). Ao ligar, faz o backfill das conversas existentes.
  def update
    enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
    @board.update!(enabled: enabled)
    RtKanban::BackfillJob.perform_later(Current.account.id) if enabled
    show
  end

  private

  def stage_json(stage, count)
    { id: stage.id, name: stage.name, color: stage.color, position: stage.position, initial: stage.initial, count_visible: count }
  end
end
