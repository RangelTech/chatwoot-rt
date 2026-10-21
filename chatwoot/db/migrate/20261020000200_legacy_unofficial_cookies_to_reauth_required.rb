# Fase CH (CH-9): canal com cookie NÃO converte em login. Os canais legados
# existentes passam a `reauth_required` (o usuário reconecta pelo assistente);
# conversas, mensagens e inbox ficam intactos e nenhuma coluna/dado é apagado.
# Idempotente: só toca linhas ainda sem `state`.
class LegacyUnofficialCookiesToReauthRequired < ActiveRecord::Migration[7.1]
  TABLES = %w[channel_facebook_unofficial channel_instagram_unofficial].freeze

  def up
    TABLES.each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
           SET state = 'reauth_required', last_error_code = 'legacy_cookie_session'
         WHERE state IS NULL
      SQL
    end
  end

  def down
    # Sem volta automática: o estado legado não é restaurado (cookie não reativa canal).
  end
end
