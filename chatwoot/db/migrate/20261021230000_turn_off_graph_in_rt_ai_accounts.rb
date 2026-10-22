# Fase L-2 (spec 10): agentes `graph` descontinuados. A flag por Account passa a nascer desligada
# e as contas que a guardavam explicitamente ligada são desligadas. Dados não são tocados.
class TurnOffGraphInRtAiAccounts < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE rt_ai_accounts SET flags = flags || '{"graph_enabled": false}'::jsonb
      WHERE flags ? 'graph_enabled' AND (flags->>'graph_enabled') = 'true'
    SQL
  end

  def down; end
end
