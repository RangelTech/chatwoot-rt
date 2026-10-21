# Base do Kanban (spec 09A): membro humano da Account; o quadro precisa estar ligado (admin pode pré-visualizar).
class Api::V1::Accounts::RtKanban::BaseController < Api::V1::Accounts::BaseController
  before_action :need_board

  private

  def need_board
    @board = RtKanban::Board.find_by(account_id: Current.account.id)
    # admin vê o quadro desligado e pode ligá-lo (flag por Account); agente continua com 404
    @board ||= RtKanban::EnsureBoard.call(Current.account) if Current.account_user.administrator?
    return head :not_found if @board.nil?
    return if @board.enabled || Current.account_user.administrator?

    head :not_found
  end

  def need_admin
    head :forbidden unless Current.account_user.administrator?
  end

  # Só avisa que o quadro mudou (sem dados do cartão); o navegador rebusca pela API autorizada.
  def broadcast_change
    ActionCable.server.broadcast("account_#{Current.account.id}",
                                 { event: 'rt_kanban.changed', data: { account_id: Current.account.id, board_id: @board.id,
                                                                       revision: @board.reload.revision } })
  end

  def visible
    RtKanban::VisibleConversations.call(account: Current.account, user: Current.user)
  end
end
