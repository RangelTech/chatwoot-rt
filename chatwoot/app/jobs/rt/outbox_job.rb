# Entrega os eventos de ciclo de vida da Account ao motor de IA. Idempotente
# no motor; aqui só cuidamos de retry com espera crescente.
class Rt::OutboxJob < ApplicationJob
  queue_as :low

  PATHS = { 'provision' => '/internal/ui/provision', 'suspend' => '/internal/ui/suspend',
            'resume' => '/internal/ui/resume', 'deprovision' => '/internal/ui/deprovision',
            'member_revoked' => '/internal/ui/member-revoked' }.freeze

  def perform
    Rt::OutboxEvent.due.limit(20).each { |event| deliver(event) }
  end

  private

  def deliver(event)
    return finish_member_revoked(event) if event.kind == 'member_revoked'

    account = Account.find_by(id: event.account_id)
    payload = { account_id: event.account_id, name: account&.name.to_s }
    result = Rt::EngineClient.post(PATHS.fetch(event.kind), payload)
    event.update!(state: 'done', last_error: nil)
    record_state(event, result, account)
  rescue StandardError => e
    mark_failed(event, e)
  end

  # Usuário removido da empresa: o motor desativa a projeção, corta as execuções e rejeita os
  # contextos anteriores. Se a pessoa já foi readicionada até a entrega, não há o que revogar.
  def finish_member_revoked(event)
    unless event.user_id && AccountUser.exists?(account_id: event.account_id, user_id: event.user_id)
      Rt::EngineClient.post(PATHS.fetch(event.kind), { account_id: event.account_id, chatwoot_user_id: event.user_id,
                                                       revoked_at: (event.occurred_at || event.created_at).to_f })
    end
    event.update!(state: 'done', last_error: nil)
  rescue StandardError => e
    mark_failed(event, e)
  end

  def mark_failed(event, error)
    exhausted = event.attempts + 1 >= Rt::OutboxEvent::MAX_ATTEMPTS
    event.update!(attempts: event.attempts + 1, last_error: error.message.truncate(500),
                  state: exhausted ? 'failed' : 'pending', run_at: Time.current + event.backoff_seconds)
    return unless exhausted

    Rt::AiAccount.find_or_create_by!(account_id: event.account_id).update!(ai_state: 'failed', last_error: error.message.truncate(500))
  end

  def record_state(event, result, account)
    ai = Rt::AiAccount.find_or_create_by!(account_id: event.account_id)
    case event.kind
    when 'provision', 'resume'
      tenant_id = result['engine_tenant_id'].presence || ai.engine_tenant_id
      raise 'motor não devolveu tenant canônico' if tenant_id.blank?

      ai.update!(engine_tenant_id: tenant_id, ai_state: 'active', last_error: nil)
      # Sem este passo a conta fica ativa no motor, mas as telas de provedores,
      # combos e uso recebem 404 do Gateway. Falhar aqui mantém o evento pendente
      # para retry, em vez de publicar um tenant parcialmente provisionado.
      Rt::GatewayClient.provision_tenant(account: account, tenant_id: tenant_id, name: account.name)
    when 'suspend', 'deprovision' then ai.update!(ai_state: 'suspended', last_error: nil)
    end
  end
end
