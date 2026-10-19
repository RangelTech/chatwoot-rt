# Base do Kanban (spec 09A): membro humano da Account; o quadro precisa estar ligado (admin pode pré-visualizar).
class Api::V1::Accounts::RtKanban::BaseController < Api::V1::Accounts::BaseController
  before_action :need_board

  private

  def need_board
    @board = RtKanban::Board.find_by(account_id: Current.account.id)
    return head :not_found if @board.nil?
    return if @board.enabled || Current.account_user.administrator?

    head :not_found
  end

  def need_admin
    head :forbidden unless Current.account_user.administrator?
  end

  def visible
    RtKanban::VisibleConversations.call(account: Current.account, user: Current.user)
  end
end
