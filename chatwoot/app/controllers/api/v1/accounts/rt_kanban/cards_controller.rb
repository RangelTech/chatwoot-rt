class Api::V1::Accounts::RtKanban::CardsController < Api::V1::Accounts::RtKanban::BaseController
  MAX_LIMIT = 50

  def index
    stage = @board.stages.find_by(id: params.require(:stage_id))
    return head :not_found if stage.nil?

    scope = RtKanban::Card.where(board_id: @board.id, stage_id: stage.id).joins(:conversation).merge(visible)
                          .includes(conversation: [:inbox, :contact, :assignee])
    scope = apply_filters(scope)
    limit = [[params.fetch(:limit, 30).to_i, 1].max, MAX_LIMIT].min
    scope = scope.where('(rt_kanban_cards.position, rt_kanban_cards.id) > (?, ?)', *decode_cursor) if params[:cursor].present?
    items = scope.order('rt_kanban_cards.position, rt_kanban_cards.id').limit(limit + 1).to_a
    next_cursor = items.size > limit ? encode_cursor(items[limit - 1]) : nil
    render json: { items: items.first(limit).map { |c| card_json(c) }, next_cursor: next_cursor, board_revision: @board.revision }
  rescue ArgumentError
    head :bad_request
  end

  def move
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = RtKanban::MoveCard.call(account: Current.account, user: Current.user, card_id: params[:id],
                                     to_stage_id: params.require(:to_stage_id), before_card_id: params[:before_card_id],
                                     expected_lock_version: params.require(:expected_lock_version),
                                     idempotency_key: params.require(:idempotency_key), request_id: request.request_id)
    broadcast_change unless result.replayed
    record_move(result.replayed ? 'replayed' : 'ok', started, result.card&.id)
    render json: { card: { id: result.card.id, stage_id: result.card.stage_id, position: result.card.position,
                           lock_version: result.card.lock_version },
                   event_id: result.event.id, board_revision: result.board_revision }
  rescue RtKanban::MoveCard::Error => e
    record_move(e.code, started, params[:id])
    render json: { code: e.code }, status: e.status
  end

  private

  def record_move(result, started, card_id)
    RtKanban::Metrics.record_move(account_id: Current.account.id, result: result, card_id: card_id, request_id: request.request_id,
                                  duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000)
  end

  VALID_STATUSES = %w[open pending snoozed resolved].freeze

  # Filtro inválido é 400 (não devolve lista vazia como se fosse resultado).
  def apply_filters(scope)
    %i[inbox_id assignee_id].each do |key|
      raise ArgumentError, key.to_s if params[key].present? && !params[key].to_s.match?(/\A\d{1,12}\z/)
    end
    scope = scope.where(conversations: { inbox_id: params[:inbox_id] }) if params[:inbox_id].present?
    scope = scope.where(conversations: { assignee_id: params[:assignee_id] }) if params[:assignee_id].present?
    unless params[:status] == 'all'
      statuses = params.fetch(:status, 'open,pending,snoozed').to_s.split(',')
      raise ArgumentError, 'status' if statuses.empty? || (statuses - VALID_STATUSES).any?

      scope = scope.where(conversations: { status: statuses })
    end
    scope = scope.where('conversations.display_id::text = ?', params[:q].to_s.strip[0, 40]) if params[:q].present?
    scope
  end

  def decode_cursor
    position, id = Base64.urlsafe_decode64(params[:cursor]).split(':', 2)
    [Integer(position), Integer(id)]
  end

  def encode_cursor(card)
    Base64.urlsafe_encode64("#{card.position}:#{card.id}")
  end

  def card_json(card)
    conversation = card.conversation
    { id: card.id, stage_id: card.stage_id, position: card.position, lock_version: card.lock_version,
      conversation: { display_id: conversation.display_id, status: conversation.status, priority: conversation.priority,
                      inbox: conversation.inbox&.name, contact: conversation.contact&.name,
                      assignee: conversation.assignee&.name, last_activity_at: conversation.last_activity_at } }
  end
end
