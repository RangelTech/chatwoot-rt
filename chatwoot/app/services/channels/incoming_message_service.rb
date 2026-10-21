# Entrada dos canais não oficiais: transforma o evento normalizado do gateway
# (webhook assinado) em contato, conversa e mensagem na caixa de entrada.
# Idempotência: source_id = message.external_id, único por inbox (trava consultiva
# + checagem). Eco (`outgoing_echo`) nunca duplica mensagem enviada por nós.
class Channels::IncomingMessageService
  FILE_KINDS = { 'image' => :image, 'video' => :video, 'audio' => :audio }.freeze
  ECHO_ADOPT_WINDOW = 5.minutes

  pattr_initialize [:channel!, :payload!]

  def perform
    case payload['type']
    when 'connection.state' then update_connection_state
    when 'message.status' then update_message_status
    when 'message.created' then create_message
    end
  end

  private

  def inbox = channel.inbox
  def event_message = payload['message'] || {}
  def external_id = event_message['external_id'].to_s
  def echo? = event_message['direction'] == 'outgoing_echo'

  def update_connection_state
    data = payload['state'] || {}
    channel.apply_connection_state!(data['state'].to_s, error_code: data['error_code'].presence, at: occurred_at)
  end

  def occurred_at
    Time.zone.parse(payload['occurred_at'].to_s) || Time.current
  rescue ArgumentError
    Time.current
  end

  def update_message_status
    status = event_message['status'].to_s
    return unless %w[delivered read failed].include?(status) && external_id.present?

    msg = inbox.messages.find_by(source_id: external_id)
    Messages::StatusUpdateService.new(msg, status, event_message['error_code']).perform if msg
    touch_activity
  end

  def create_message
    return if external_id.blank? || inbox.blank?

    created = nil
    ActiveRecord::Base.transaction do
      lock_message_key
      next if inbox.messages.exists?(source_id: external_id)
      next if adopt_echo_of_own_message

      created = persist_message
    end
    touch_activity
    attach_files(created) if created
    created
  end

  def lock_message_key
    key = "#{channel.account_id}:#{channel.id}:#{external_id}"
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', key])
    )
  end

  # Eco de mensagem que NÓS enviamos pode chegar antes de gravarmos o source_id da resposta
  # do gateway: casa por conteúdo recente e adota o external_id em vez de criar duplicata.
  def adopt_echo_of_own_message
    return false unless echo?

    pending = inbox.messages.outgoing.where(source_id: nil, content: event_message['text'].to_s)
                   .where('messages.created_at > ?', ECHO_ADOPT_WINDOW.ago).order(:id).last
    return false unless pending

    pending.update!(source_id: external_id)
    true
  end

  def persist_message
    contact_inbox = find_contact_inbox
    conversation = find_conversation(contact_inbox)
    conversation.messages.create!(
      content: event_message['text'].to_s,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: echo? ? :outgoing : :incoming,
      sender: (contact_inbox.contact unless echo?),
      source_id: external_id,
      content_attributes: reply_attributes
    )
  end

  def reply_attributes
    reply = event_message['reply_to']
    reply.present? ? { in_reply_to_external_id: reply.to_s } : {}
  end

  def find_contact_inbox
    contact = payload.dig('conversation', 'contact') || {}
    ref = payload.dig('conversation', 'external_id').to_s
    ContactInboxWithContactBuilder.new(
      source_id: ref,
      inbox: inbox,
      contact_attributes: {
        name: contact['name'].presence || contact['username'].presence || ref,
        additional_attributes: { 'username' => contact['username'], 'external_id' => contact['external_id'] }.compact,
        avatar_url: contact['avatar_url']
      }.compact
    ).perform
  end

  def find_conversation(contact_inbox)
    scope = contact_inbox.conversations
    existing = inbox.lock_to_single_conversation ? scope.last : scope.where.not(status: :resolved).last
    existing || Conversation.create!(account_id: inbox.account_id, inbox_id: inbox.id,
                                     contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id)
  end

  def attach_files(message)
    Array(event_message['attachments']).each do |att|
      attach_file(message, att)
    rescue Channels::GatewayClient::Error => e
      Rails.logger.warn("channels attachment download failed: #{e.code}")
    end
  end

  def attach_file(message, att)
    file = Channels::GatewayClient.new(account_id: channel.account_id).download(att['url'])
    name = att['name'].presence || "#{att['kind']}-#{SecureRandom.hex(4)}"
    attachment = message.attachments.new(account_id: message.account_id, file_type: FILE_KINDS.fetch(att['kind'].to_s, :file))
    attachment.file.attach(io: StringIO.new(file[:body]), filename: name, content_type: att['mime'].presence || file[:content_type])
    attachment.save!
  end

  def touch_activity
    channel.update_columns(last_activity_at: occurred_at, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
