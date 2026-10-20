# Fase F (spec 10, F-1): filas com respondente humano ou IA. Tabelas `rt_*`; nenhuma tabela do Chatwoot muda.
class CreateRtRouting < ActiveRecord::Migration[7.1]
  def change
    create_table :rt_queue_bindings do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :team, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :respondent_kind, null: false, default: 'humano'
      t.string :template_id
      t.string :mode, null: false, default: 'desligado'
      t.bigint :allowed_destination_team_ids, array: true, null: false, default: []
      t.text :description
      t.timestamps
    end

    create_table :rt_inbox_entry_queues do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.references :team, null: true, foreign_key: { on_delete: :nullify }
      # legado | sombra | filas: interruptor por caixa de entrada (volta imediata ao legado).
      t.string :routing_mode, null: false, default: 'legado'
      # Estado anterior (F-4) para o rollback da migração.
      t.jsonb :legacy_snapshot, null: false, default: {}
      t.timestamps
    end

    create_table :rt_routing_events do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :from_team_id
      t.bigint :to_team_id
      t.string :actor_kind, null: false, default: 'system'
      t.bigint :actor_id
      t.string :reason
      t.string :run_id
      t.datetime :created_at, null: false
    end
    add_index :rt_routing_events, [:conversation_id, :created_at]
    add_index :rt_routing_events, [:account_id, :created_at]

    create_table :rt_routing_shadow_log do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :message_id
      t.jsonb :legacy_decision, null: false, default: {}
      t.jsonb :derived_decision, null: false, default: {}
      t.boolean :diverged, null: false, default: false
      t.datetime :created_at, null: false
    end
    add_index :rt_routing_shadow_log, [:account_id, :created_at]
    add_index :rt_routing_shadow_log, :diverged, where: 'diverged'
  end
end
