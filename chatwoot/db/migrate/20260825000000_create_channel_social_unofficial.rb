# Produto-10 (25/08/2026): Facebook e Instagram "não oficiais" -- credencial
# é a sessão do navegador (cookies), não API key nem par (project_id, token)
# como WAPI. Mesmo padrão de tabela por canal já usado (channel_wapi,
# channel_evolution_api). `cookies` fica cifrado via `encrypts` do Rails
# (ActiveRecord Encryption, mesmo padrão de `token`/`api_key` -- nome de
# coluna SEM sufixo `_encrypted`, é o próprio Rails quem cifra em cima).
class CreateChannelSocialUnofficial < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_facebook_unofficial do |t|
      t.integer :account_id, null: false
      t.text :cookies, null: false # cifrado via `encrypts :cookies` no model; JSON serializado por dentro
      t.string :external_label # nome/perfil exibido, não sensível
      t.string :webhook_verify_token, null: false
      t.jsonb :connection_status, null: false, default: {}
      t.datetime :connection_status_checked_at
      t.datetime :last_polled_at

      t.timestamps
    end
    add_index :channel_facebook_unofficial, :account_id

    create_table :channel_instagram_unofficial do |t|
      t.integer :account_id, null: false
      t.text :cookies, null: false
      t.string :external_label
      t.string :webhook_verify_token, null: false
      t.jsonb :connection_status, null: false, default: {}
      t.datetime :connection_status_checked_at
      t.datetime :last_polled_at

      t.timestamps
    end
    add_index :channel_instagram_unofficial, :account_id
  end
end
