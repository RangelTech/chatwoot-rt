# Fase CH (CH-6/CH-9/CH-10): canais não oficiais passam a ser conectados por
# usuário/senha ou QR através do gateway de canais (sem cookie, sem polling).
# Nasce uma tabela por canal novo e os dois canais legados (cookies) ganham as
# colunas do novo miolo. Nada é removido: `cookies` só deixa de ser obrigatório.
class CreateChannelUnofficialGateway < ActiveRecord::Migration[7.1]
  NEW_TABLES = %i[channel_messenger_unofficial channel_whatsapp_unofficial channel_tiktok_unofficial].freeze
  LEGACY_TABLES = %i[channel_facebook_unofficial channel_instagram_unofficial].freeze
  NEW_COLUMNS = {
    connection_id: :uuid,
    state: :string,
    webhook_secret: :text, # cifrado via `encrypts` no model
    last_error_code: :string,
    last_activity_at: :datetime,
    connector_version: :string
  }.freeze

  def up
    NEW_TABLES.each do |table|
      create_table table do |t|
        t.integer :account_id, null: false
        t.string :external_label
        t.timestamps
      end
      add_index table, :account_id
      add_gateway_columns(table)
    end

    LEGACY_TABLES.each do |table|
      add_gateway_columns(table)
      change_column_null table, :cookies, true
    end
  end

  def down
    LEGACY_TABLES.each do |table|
      remove_gateway_columns(table)
    end
    NEW_TABLES.each { |table| drop_table table }
  end

  private

  def add_gateway_columns(table)
    NEW_COLUMNS.each do |name, type|
      add_column table, name, type
    end
    add_index table, :connection_id, unique: true, where: 'connection_id IS NOT NULL'
  end

  def remove_gateway_columns(table)
    remove_index table, :connection_id
    NEW_COLUMNS.each_key { |name| remove_column table, name }
  end
end
