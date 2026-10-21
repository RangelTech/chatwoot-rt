# Webhook de entrada do gateway de canais (Fase CH). Sem sessão de usuário: a autenticação é
# a assinatura HMAC-SHA256 de "<timestamp>.<corpo bruto>" com o webhook_secret do canal.
# Rejeita timestamp fora de +-300 s, assinatura inválida (comparação em tempo constante)
# e event_id repetido (replay).
class Webhooks::ChannelsController < ActionController::API
  MAX_SKEW = 300
  REPLAY_TTL = 1.day.to_i

  before_action :load_channel
  before_action :verify_signature

  def process_payload
    event_id = request.headers['X-Luar-Event-Id'].to_s
    return render(json: { error: 'invalid_event' }, status: :bad_request) if event_id.blank? || payload.blank?
    return render(json: { error: 'replay' }, status: :conflict) unless claim_event(event_id)

    begin
      Channels::IncomingMessageService.new(channel: @channel, payload: payload).perform
    rescue StandardError
      release_event(event_id)
      raise
    end
    head :ok
  end

  private

  def load_channel
    klass = UnofficialGatewayChannel.channel_class_for_type(params[:channel_type])
    @channel = klass&.find_by(id: params[:id])
    head :not_found unless @channel
  end

  def verify_signature
    secret = @channel.webhook_secret.to_s
    timestamp = request.headers['X-Luar-Timestamp'].to_s
    provided = request.headers['X-Luar-Signature'].to_s.delete_prefix('sha256=')
    return head :unauthorized if secret.empty? || provided.empty? || !timestamp.match?(/\A\d{1,12}\z/)
    return head :unauthorized if (Time.current.to_i - timestamp.to_i).abs > MAX_SKEW

    expected = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{request.raw_post}")
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, provided)
  end

  def payload
    @payload ||= begin
      parsed = JSON.parse(request.raw_post)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end

  def replay_key(event_id)
    "channels:webhook:#{@channel.class.name}:#{@channel.id}:#{event_id}"
  end

  def claim_event(event_id)
    Redis::Alfred.set(replay_key(event_id), '1', nx: true, ex: REPLAY_TTL)
  end

  def release_event(event_id)
    Redis::Alfred.delete(replay_key(event_id))
  end
end
