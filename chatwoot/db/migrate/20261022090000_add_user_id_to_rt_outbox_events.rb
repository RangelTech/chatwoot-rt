# Eventos de membro (member_revoked) carregam o usuário removido; os de ciclo de vida da Account
# seguem sem ele. Expand: coluna nula, nada a preencher.
class AddUserIdToRtOutboxEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :rt_outbox_events, :user_id, :bigint
    add_column :rt_outbox_events, :occurred_at, :datetime
  end
end
