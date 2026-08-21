class CreateChannelEvolutionApi < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_evolution_api do |t|
      t.integer :account_id, null: false
      t.string :instance_name, null: false
      t.string :api_url, null: false
      t.string :api_key, null: false
      t.string :webhook_verify_token, null: false
      t.jsonb :connection_status, null: false, default: {}
      t.datetime :connection_status_checked_at
      t.text :qr_code

      t.timestamps
    end

    add_index :channel_evolution_api, :instance_name, unique: true
    add_index :channel_evolution_api, :account_id
  end
end
