# Spec 11 §20: plano do tenant (variável de permissionamento).
class AddPlanToRtAiAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :rt_ai_accounts, :plan, :string, null: false, default: 'nova'
    add_column :rt_ai_accounts, :plan_changed_at, :datetime
    execute "UPDATE rt_ai_accounts SET plan = 'eclipse'"
    execute "UPDATE rt_ai_accounts SET plan = 'interno' WHERE account_id = 14"
  end

  def down
    remove_column :rt_ai_accounts, :plan_changed_at
    remove_column :rt_ai_accounts, :plan
  end
end
