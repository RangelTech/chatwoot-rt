# Gera uma senha provisória, exibida uma única vez a quem a pediu (Super Admin
# ou administrador da Account). A pessoa troca no primeiro acesso.
class Rt::ProvisionalPassword
  def self.issue!(user)
    password = "#{SecureRandom.alphanumeric(12)}#{%w[! # $ %].sample}aA1"
    user.update!(password: password, password_confirmation: password)
    user.update!(custom_attributes: (user.custom_attributes || {}).merge('must_change_password' => true))
    password
  end
end
