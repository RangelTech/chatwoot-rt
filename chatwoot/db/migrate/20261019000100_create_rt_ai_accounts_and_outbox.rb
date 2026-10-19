# U-1b (spec 10): vínculo Account <-> motor de IA (fonte única) e fila
# transacional de eventos de ciclo de vida. A Account nunca falha porque o
# motor está fora: o evento fica na fila e é reenviado.
class CreateRtAiAccountsAndOutbox < ActiveRecord::Migration[7.1]
  def change
    create_table :rt_ai_accounts do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.uuid :engine_tenant_id, index: { unique: true }
      t.string :ai_state, null: false, default: 'pending'
      t.text :last_error
      t.jsonb :flags, null: false, default: {}
      t.timestamps
    end

    create_table :rt_outbox_events do |t|
      t.bigint :account_id, null: false, index: true
      t.string :kind, null: false
      t.string :state, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.datetime :run_at, null: false, default: -> { 'now()' }
      t.text :last_error
      t.timestamps
    end
    add_index :rt_outbox_events, [:state, :run_at]
  end
end
