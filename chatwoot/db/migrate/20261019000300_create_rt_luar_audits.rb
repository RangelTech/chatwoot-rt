# H-6: auditoria do proxy Luar (somente metadados).
class CreateRtLuarAudits < ActiveRecord::Migration[7.1]
  def change
    create_table :rt_luar_audits do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :run_id
      t.string :http_method, null: false
      t.string :path, null: false
      t.integer :status, null: false
      t.datetime :created_at, null: false
    end
    add_index :rt_luar_audits, [:account_id, :created_at]
    add_index :rt_luar_audits, [:user_id, :created_at]
  end
end
