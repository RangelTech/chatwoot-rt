# Senha provisória (spec 10, U-1c): a pessoa entra com a senha entregue pelo
# administrador e é obrigada a trocá-la; a troca limpa o marcador.
module Rt::UserProvisionalPassword
  extend ActiveSupport::Concern

  prepended do
    after_update :clear_must_change_password, if: :saved_change_to_encrypted_password?
  end

  def must_change_password?
    custom_attributes&.dig('must_change_password') == true
  end

  private

  def clear_must_change_password
    return unless must_change_password?

    update_column(:custom_attributes, custom_attributes.except('must_change_password')) # rubocop:disable Rails/SkipsModelValidations
  end
end
