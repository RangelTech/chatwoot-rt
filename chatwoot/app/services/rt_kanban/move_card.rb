# Move um cartão (entre colunas ou dentro da coluna) com trava otimista, ordem estável e evento no mesmo commit.
class RtKanban::MoveCard
  class Error < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      super(code)
      @status = status
      @code = code
    end
  end

  Result = Struct.new(:card, :event, :board_revision, :replayed, keyword_init: true)

  def self.call(account:, user:, card_id:, to_stage_id:, before_card_id:, expected_lock_version:, idempotency_key:, request_id: nil)
    new(account, user, card_id, to_stage_id, before_card_id, expected_lock_version, idempotency_key, request_id).call
  end

  def initialize(account, user, card_id, to_stage_id, before_card_id, expected_lock_version, idempotency_key, request_id)
    @account = account
    @user = user
    @card_id = card_id
    @to_stage_id = to_stage_id
    @before_card_id = before_card_id
    @expected = expected_lock_version
    @key = idempotency_key.to_s
    @request_id = request_id
  end

  def call
    raise Error.new(422, 'invalid_idempotency_key') unless @key.match?(/\A[0-9a-zA-Z_-]{8,64}\z/)

    visible = RtKanban::VisibleConversations.call(account: @account, user: @user)
    card = RtKanban::Card.where(account_id: @account.id).joins(:conversation).merge(visible).find_by(id: @card_id)
    raise Error.new(404, 'not_found') if card.nil?

    replay = replayed_result
    return replay if replay

    RtKanban::Card.transaction do
      stages = RtKanban::Stage.where(board_id: card.board_id, id: [card.stage_id, @to_stage_id]).order(:id).lock.to_a
      target = stages.find { |s| s.id == @to_stage_id.to_i }
      raise Error.new(422, 'invalid_stage') if target.nil?

      card.lock!
      raise Error.new(409, 'stale_version') if card.lock_version != @expected.to_i

      from_stage_id = card.stage_id
      position = position_for(card, target)
      card.update!(stage_id: target.id, position: position) # lock_version sobe sozinho (travamento otimista do Rails)
      board = card.board
      board.increment!(:revision) # rubocop:disable Rails/SkipsModelValidations
      event = RtKanban::Event.create!(account_id: @account.id, board_id: board.id, card_id_snapshot: card.id,
                                      conversation_id_snapshot: card.conversation_id, from_stage_id_snapshot: from_stage_id,
                                      to_stage_id_snapshot: target.id, action: 'moved', actor_user_id: @user.id, source: 'ui',
                                      request_id: @request_id, idempotency_key: @key, request_digest: digest,
                                      to_position: card.position, to_lock_version: card.lock_version,
                                      board_revision_after: board.revision, created_at: Time.current)
      Result.new(card: card, event: event, board_revision: board.revision, replayed: false)
    end
  rescue ActiveRecord::StaleObjectError
    raise Error.new(409, 'stale_version')
  rescue ActiveRecord::RecordNotUnique
    replayed_result || raise(Error.new(409, 'idempotency_conflict'))
  end

  private

  def digest
    Digest::SHA256.hexdigest([@card_id, @to_stage_id, @before_card_id, @expected].join('|'))
  end

  def replayed_result
    event = RtKanban::Event.find_by(account_id: @account.id, actor_user_id: @user.id, idempotency_key: @key)
    return nil unless event
    raise Error.new(409, 'idempotency_conflict') unless event.request_digest == digest

    card = RtKanban::Card.find_by(id: event.card_id_snapshot)
    Result.new(card: card, event: event, board_revision: event.board_revision_after, replayed: true)
  end

  # Fim da coluna, ou imediatamente antes de `before_card_id` (ponto médio; renumera a coluna se não houver espaço).
  def position_for(card, target)
    siblings = RtKanban::Card.where(stage_id: target.id).where.not(id: card.id).order(:position, :id)
    return (siblings.maximum(:position) || 0) + RtKanban::Card::GAP if @before_card_id.blank?

    before = siblings.find_by(id: @before_card_id)
    raise Error.new(422, 'invalid_anchor') if before.nil?

    previous = siblings.where('position < ?', before.position).maximum(:position) || 0
    return (previous + before.position) / 2 if before.position - previous > 1

    renumber!(siblings)
    before.reload
    ((siblings.where('position < ?', before.position).maximum(:position) || 0) + before.position) / 2
  end

  def renumber!(siblings)
    siblings.each_with_index do |s, i|
      s.update_columns(position: (i + 1) * RtKanban::Card::GAP * 2) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
