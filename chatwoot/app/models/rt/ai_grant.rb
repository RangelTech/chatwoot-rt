# == Schema Information
#
# Table name: rt_ai_grants
#
#  id              :bigint           not null, primary key
#  role_key        :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_user_id :bigint           not null
#
# Indexes
#
#  index_rt_ai_grants_on_account_user_id  (account_user_id) UNIQUE
#
class Rt::AiGrant < ApplicationRecord
  self.table_name = 'rt_ai_grants'

  belongs_to :account_user

  validates :role_key, inclusion: { in: Rt::AiRoles::ROLES.keys }
end
