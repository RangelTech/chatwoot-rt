class Api::V1::Accounts::RtKanban::EventsController < Api::V1::Accounts::RtKanban::BaseController
  def index
    conversation = visible.find_by(display_id: params.require(:conversation_display_id))
    return head :not_found if conversation.nil?

    events = RtKanban::Event.where(account_id: Current.account.id, conversation_id_snapshot: conversation.id)
                            .order(:created_at, :id).limit(30)
    render json: events.map { |e| e.slice(:id, :action, :from_stage_id_snapshot, :to_stage_id_snapshot, :actor_user_id, :source, :created_at) }
  end
end
