# Builds a Chatwoot conversation/message from a WAPI inbound-message webhook
# payload. Kept intentionally close to Sms::IncomingMessageService — WAPI is a
# generic non-official WhatsApp HTTP provider, not the Meta Cloud API, so we
# don't reuse Channel::Whatsapp's Meta-specific pipeline.
#
# Expected params (normalized by Webhooks::WapiEventsJob before this is called):
#   from    - sender phone number (string)
#   text    - message body (string)
#   id      - provider message id, used as source_id for idempotency
class Wapi::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if duplicate_message?

    set_contact
    set_conversation
    @message = @conversation.messages.create!(
      content: params[:text],
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: params[:id]
    )
  end

  private

  def duplicate_message?
    params[:id].present? && @inbox.messages.exists?(source_id: params[:id])
  end

  def phone_number
    params[:from]
  end

  def formatted_phone_number
    TelephoneNumber.parse(phone_number).international_number
  rescue StandardError
    phone_number
  end

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: params[:from],
      inbox: @inbox,
      contact_attributes: contact_attributes
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def contact_attributes
    {
      name: formatted_phone_number,
      phone_number: phone_number
    }
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end

  def set_conversation
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end
end
