# K1 (spec 09A): quadro único por Account, cartão = Conversation, histórico append-only.
class CreateRtKanban < ActiveRecord::Migration[7.1]
  def change
    create_table :rt_kanban_boards do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, default: 'Conversas'
      t.boolean :enabled, null: false, default: false
      t.bigint :revision, null: false, default: 0
      t.timestamps
    end

    create_table :rt_kanban_stages do |t|
      t.references :board, null: false, foreign_key: { to_table: :rt_kanban_boards, on_delete: :cascade }
      t.string :name, null: false
      t.string :color, null: false, default: '#64748b'
      t.integer :position, null: false
      t.boolean :initial, null: false, default: false
      t.timestamps
    end
    add_index :rt_kanban_stages, [:board_id, :position], unique: true
    add_index :rt_kanban_stages, :board_id, unique: true, where: 'initial', name: 'index_rt_kanban_stages_one_initial'

    create_table :rt_kanban_cards do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :board, null: false, foreign_key: { to_table: :rt_kanban_boards, on_delete: :cascade }
      t.references :stage, null: false, foreign_key: { to_table: :rt_kanban_stages }
      t.references :conversation, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.bigint :position, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :rt_kanban_cards, [:board_id, :stage_id, :position, :id], name: 'index_rt_kanban_cards_order'
    add_index :rt_kanban_cards, [:account_id, :conversation_id], unique: true

    create_table :rt_kanban_events do |t|
      t.bigint :account_id, null: false
      t.bigint :board_id
      t.bigint :card_id_snapshot
      t.bigint :conversation_id_snapshot
      t.bigint :from_stage_id_snapshot
      t.bigint :to_stage_id_snapshot
      t.string :action, null: false
      t.bigint :actor_user_id
      t.string :source, null: false, default: 'system'
      t.string :request_id
      t.string :idempotency_key
      t.string :request_digest
      t.bigint :to_position
      t.integer :to_lock_version
      t.bigint :board_revision_after
      t.datetime :created_at, null: false
    end
    add_index :rt_kanban_events, [:account_id, :conversation_id_snapshot, :created_at, :id], name: 'index_rt_kanban_events_conversation'
    add_index :rt_kanban_events, [:account_id, :actor_user_id, :idempotency_key], unique: true,
                                                                                  where: 'idempotency_key IS NOT NULL',
                                                                                  name: 'index_rt_kanban_events_idempotency'
  end
end
