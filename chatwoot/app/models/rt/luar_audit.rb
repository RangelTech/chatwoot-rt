# == Schema Information
#
# Table name: rt_luar_audits
#
#  id         :bigint           not null, primary key
#  http_method :string           not null
#  path       :string           not null
#  status     :integer          not null
#  created_at :datetime         not null
#  account_id :bigint           not null
#  run_id     :string
#  user_id    :bigint           not null
#
# Auditoria do proxy Luar: só metadados, nunca corpo de mensagem nem query.
class Rt::LuarAudit < ApplicationRecord
  self.table_name = 'rt_luar_audits'
end
