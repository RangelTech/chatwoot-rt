class Api::V1::Accounts::RtKanban::StagesController < Api::V1::Accounts::RtKanban::BaseController
  before_action :need_admin
  before_action :find_stage, only: [:update, :destroy]

  def create
    position = (@board.stages.maximum(:position) || 0) + RtKanban::Card::GAP
    stage = @board.stages.create!(stage_params.merge(position: position))
    @board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
    render json: stage, status: :created
  end

  # Renomeia/recolore e, com `before_stage_id` (vazio = fim), reordena as etapas na mesma transação.
  def update
    ok = false
    RtKanban::Stage.transaction do
      @board.lock!
      @stage.update!(stage_params)
      ok = reorder!
      raise ActiveRecord::Rollback unless ok

      @board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
    end
    return render json: { code: 'invalid_anchor' }, status: :unprocessable_entity unless ok

    broadcast_change
    render json: @stage
  end

  # Etapa com cartões só sai com destino explícito; a inicial nunca sai.
  def destroy
    return render json: { code: 'initial_stage' }, status: :unprocessable_entity if @stage.initial

    if @stage.cards.exists?
      target = @board.stages.find_by(id: params[:move_to_stage_id])
      return render json: { code: 'move_to_required' }, status: :conflict if target.nil? || target.id == @stage.id

      # lock_version sobe junto: quem tinha o cartão aberto na etapa antiga leva 409 em vez de gravar às cegas
      RtKanban::Card.where(stage_id: @stage.id).update_all(stage_id: target.id, # rubocop:disable Rails/SkipsModelValidations
                                                           lock_version: Arel.sql('lock_version + 1'))
    end
    @stage.destroy!
    @board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
    broadcast_change
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

  # Reordena só quando `before_stage_id` veio na requisição. Duas passadas (negativo, depois final) para não bater
  # no índice único (board_id, position). Devolve false se a âncora não existe.
  def reorder!
    return true unless params.key?(:before_stage_id)

    others = @board.stages.reload.to_a.reject { |s| s.id == @stage.id }
    if params[:before_stage_id].present?
      index = others.index { |s| s.id == params[:before_stage_id].to_i }
      return false if index.nil?

      others.insert(index, @stage)
    else
      others << @stage
    end
    others.each_with_index { |s, i| s.update_columns(position: -(i + 1)) } # rubocop:disable Rails/SkipsModelValidations
    others.each_with_index { |s, i| s.update_columns(position: (i + 1) * RtKanban::Card::GAP) } # rubocop:disable Rails/SkipsModelValidations
    true
  end
end
