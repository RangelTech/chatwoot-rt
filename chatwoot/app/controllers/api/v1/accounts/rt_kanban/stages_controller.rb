class Api::V1::Accounts::RtKanban::StagesController < Api::V1::Accounts::RtKanban::BaseController
  before_action :need_admin
  before_action :find_stage, only: [:update, :destroy]

  def create
    position = (@board.stages.maximum(:position) || 0) + RtKanban::Card::GAP
    stage = @board.stages.create!(stage_params.merge(position: position))
    @board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
    render json: stage, status: :created
  end

  def update
    @stage.update!(stage_params)
    @board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
    render json: @stage
  end

  # Etapa com cartões só sai com destino explícito; a inicial nunca sai.
  def destroy
    return render json: { code: 'initial_stage' }, status: :unprocessable_entity if @stage.initial

    if @stage.cards.exists?
      target = @board.stages.find_by(id: params[:move_to_stage_id])
      return render json: { code: 'move_to_required' }, status: :conflict if target.nil? || target.id == @stage.id

      RtKanban::Card.where(stage_id: @stage.id).update_all(stage_id: target.id) # rubocop:disable Rails/SkipsModelValidations
    end
    @stage.destroy!
    @board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
    head :no_content
  end

  private

  def find_stage
    @stage = @board.stages.find_by(id: params[:id])
    head :not_found if @stage.nil?
  end

  def stage_params
    params.permit(:name, :color)
  end
end
