# Fase F: carrega o estado real da conversa e aplica o Resolver. Em modo `filas` atribui a fila de entrada
# quando a conversa ainda nao tem fila; em `sombra` e `legado` nunca altera nada.
class Rt::Routing::Resolve
  AGENT_CACHE_TTL = 60

  def self.call(conversation, legacy: nil)
    new(conversation, legacy).call
  end

  def initialize(conversation, legacy)
    @conversation = conversation
    @legacy = legacy
  end

  def call
    entry = Rt::InboxEntryQueue.find_by(inbox_id: @conversation.inbox_id)
    mode = entry&.routing_mode || 'legado'
    decision = resolve(entry)
    applied = false
    applied = apply_entry_queue(decision, entry) if mode == 'filas' && decision[:apply_entry_queue]
    log_shadow(decision) if mode == 'sombra' && !@legacy.nil?
    decision.merge(routing_mode: mode, conversation_id: @conversation.display_id, applied: applied)
  end

  private

  def resolve(entry)
    team_id = @conversation.team_id
    binding = binding_for(team_id || entry&.team_id)
    Rt::Routing::Resolver.call(
      status: @conversation.status, team_id: team_id, assignee_id: @conversation.assignee_id,
      entry_team_id: entry&.team_id, binding: binding, agent_published: published?(binding)
    )
  end

  def binding_for(team_id)
    return nil unless team_id

    row = Rt::QueueBinding.find_by(team_id: team_id)
    row && Rt::Routing::Resolver::QueueInfo.new(respondent_kind: row.respondent_kind, mode: row.mode, template_id: row.template_id)
  end

  # Agente nao confirmado como publicado conta como nao publicado (a fila para de responder, a conversa segue visivel).
  def published?(binding)
    return false unless binding&.respondent_kind == 'ia' && binding.template_id.present?

    Rails.cache.fetch("rt:routing:published:#{@conversation.account_id}:#{binding.template_id}", expires_in: AGENT_CACHE_TTL) do
      Rt::Routing::TemplateLookup.published?(account: @conversation.account, template_id: binding.template_id) == true
    end
  end

  def apply_entry_queue(decision, entry)
    @conversation.update!(team_id: entry.team_id)
    decision[:apply_entry_queue] = false
    true
  end

  def log_shadow(decision)
    diverged = @legacy.to_s != decision[:respondent]
    Rt::RoutingShadowLog.create!(account_id: @conversation.account_id, conversation_id: @conversation.id,
                                 legacy_decision: { respondent: @legacy.to_s },
                                 derived_decision: decision.slice(:respondent, :agent, :queue_id, :reason), diverged: diverged)
  end
end
