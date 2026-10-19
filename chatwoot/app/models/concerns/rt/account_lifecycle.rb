# Ganchos de ciclo de vida da Account -> fila (`rt_outbox_events`). A Account é a
# empresa (tenant); o motor de IA reage. Nunca apaga dados: excluir a Account
# só desliga a empresa no motor.
module Rt::AccountLifecycle
  extend ActiveSupport::Concern

  prepended do
    after_create_commit { Rt::AccountLifecycle.enqueue(id, 'provision') }
    after_update_commit :enqueue_status_change, if: :saved_change_to_status?
    after_destroy_commit { Rt::AccountLifecycle.enqueue(id, 'deprovision') }
  end

  def self.enqueue(account_id, kind)
    return if ENV['RT_ENGINE_URL'].blank?

    Rt::OutboxEvent.create!(account_id: account_id, kind: kind)
    Rt::OutboxJob.perform_later
  end

  def ai_state
    Rt::AiAccount.find_by(account_id: id)&.ai_state || 'pending'
  end

  def ai_last_error
    Rt::AiAccount.find_by(account_id: id)&.last_error
  end

  private

  def enqueue_status_change
    Rt::AccountLifecycle.enqueue(id, suspended? ? 'suspend' : 'resume')
  end
end
