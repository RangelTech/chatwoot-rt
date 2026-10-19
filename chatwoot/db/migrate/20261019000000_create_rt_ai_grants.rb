# U-1a (spec 10): perfil de IA por membro da Account. O papel nativo
# (administrator/agent) define o perfil padrão; esta tabela guarda só a
# exceção atribuída por um administrador (Gestor, Leitor, etc.).
class CreateRtAiGrants < ActiveRecord::Migration[7.1]
  def change
    create_table :rt_ai_grants do |t|
      t.references :account_user, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :role_key, null: false
      t.timestamps
    end
  end
end
