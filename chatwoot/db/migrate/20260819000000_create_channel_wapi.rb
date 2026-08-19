class CreateChannelWapi < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_wapi do |t|
      t.integer :account_id, null: false
      t.string :project_id, null: false
      t.string :token, null: false
      t.string :webhook_verify_token, null: false
      t.jsonb :connection_status, null: false, default: {}
      t.datetime :connection_status_checked_at

      t.timestamps
    end

    add_index :channel_wapi, :project_id, unique: true
    add_index :channel_wapi, :account_id
  end
end
