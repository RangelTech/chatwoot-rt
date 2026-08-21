class Evolution::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if from_me? || text.blank? || duplicate_message?

    contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: sender_id,
      inbox: inbox,
      contact_attributes: { name: sender_name, phone_number: phone_number }
    ).perform
    conversation = existing_conversation(contact_inbox) || Conversation.create!(conversation_params(contact_inbox))
    conversation.messages.create!(
      content: text,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      source_id: message_id
    )
  end

  private

  def data = params[:data].with_indifferent_access
  def key = data[:key].with_indifferent_access
  def message = data[:message].with_indifferent_access
  def sender_id = key[:remoteJid]
  def message_id = key[:id]
  def from_me? = key[:fromMe] == true
  def text = message[:conversation] || message.dig(:extendedTextMessage, :text)
  def sender_name = data[:pushName].presence || sender_id
  def phone_number = sender_id.to_s.end_with?('@s.whatsapp.net') ? sender_id.delete_suffix('@s.whatsapp.net') : nil
  def duplicate_message? = message_id.present? && inbox.messages.exists?(source_id: message_id)

  def existing_conversation(contact_inbox)
    inbox.lock_to_single_conversation ? contact_inbox.conversations.last : contact_inbox.conversations.where.not(status: :resolved).last
  end

  def conversation_params(contact_inbox)
    { account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id }
  end
end
