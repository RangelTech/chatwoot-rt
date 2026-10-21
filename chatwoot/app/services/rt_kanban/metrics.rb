# Métricas do quadro (K5): contadores por resultado e latência média do movimento, por Account, em Redis,
# mais uma linha de log JSON (sem conteúdo de conversa). Falha de métrica nunca derruba a requisição.
class RtKanban::Metrics
  RESULTS = %w[ok replayed stale_version idempotency_conflict invalid_stage invalid_anchor invalid_idempotency_key not_found
               forbidden error].freeze
  TTL = 90.days.to_i

  def self.key(account_id)
    "rt_kanban:metrics:#{account_id}"
  end

  def self.record_move(account_id:, result:, card_id: nil, duration_ms: 0, request_id: nil)
    result = 'error' unless RESULTS.include?(result)
    Redis::Alfred.with do |conn|
      conn.hincrby(key(account_id), "move_total:#{result}", 1)
      conn.hincrby(key(account_id), 'move_ms_sum', duration_ms.to_i)
      conn.hincrby(key(account_id), 'move_ms_count', 1)
      conn.expire(key(account_id), TTL)
    end
    Rails.logger.info({ event: 'rt_kanban.move', result: result, account_id: account_id, card_id: card_id,
                        duration_ms: duration_ms.to_i, request_id: request_id }.to_json)
  rescue StandardError => e
    Rails.logger.warn("rt_kanban metrics failed: #{e.class}")
  end

  def self.snapshot(account)
    raw = Redis::Alfred.with { |conn| conn.hgetall(key(account.id)) }
    totals = RESULTS.index_with { |r| raw["move_total:#{r}"].to_i }
    count = raw['move_ms_count'].to_i
    board = RtKanban::Board.find_by(account_id: account.id)
    {
      move_total: totals,
      move_latency_ms_avg: count.zero? ? nil : (raw['move_ms_sum'].to_i.to_f / count).round(1),
      board_revision: board&.revision,
      events_24h: RtKanban::Event.where(account_id: account.id).where('created_at > ?', 24.hours.ago).count,
      reconcile: RtKanban::Reconcile.call(account)
    }
  rescue StandardError => e
    Rails.logger.warn("rt_kanban metrics snapshot failed: #{e.class}")
    { error: 'unavailable' }
  end
end
