# Fase F: fila de entrada da caixa e interruptor de roteamento (legado | sombra | filas).
class Rt::InboxEntryQueue < ApplicationRecord
  self.table_name = 'rt_inbox_entry_queues'

  MODES = %w[legado sombra filas].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :team, optional: true

  validates :routing_mode, inclusion: { in: MODES }
  validates :inbox_id, uniqueness: true
  validate :same_account
  validate :entry_required_outside_legacy

  # Modo efetivo de uma caixa: sem registro = legado.
  def self.mode_for(inbox_id)
    where(inbox_id: inbox_id).pick(:routing_mode) || 'legado'
  end

  private

  def same_account
    errors.add(:inbox, 'must belong to the account') if inbox && inbox.account_id != account_id
    errors.add(:team, 'must belong to the account') if team && team.account_id != account_id
  end

  def entry_required_outside_legacy
    errors.add(:team, 'entry queue is required to leave legacy mode') if routing_mode != 'legado' && team_id.blank?
  end
end
