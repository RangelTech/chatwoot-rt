# Fase F (F-8d): retrato somente leitura de quem responde a conversa, para o indicador do cabecalho.
# Nao aplica fila de entrada nem grava log; em modo legado nao afirma nada.
class Rt::Routing::RespondentView
  def self.call(conversation)
    entry = Rt::InboxEntryQueue.find_by(inbox_id: conversation.inbox_id)
    mode = entry&.routing_mode || 'legado'
    return { routing_mode: mode, respondent: nil } if mode == 'legado'

    team_id = conversation.team_id || entry&.team_id
    row = team_id && Rt::QueueBinding.find_by(team_id: team_id)
    binding = row && Rt::Routing::Resolver::QueueInfo.new(respondent_kind: row.respondent_kind, mode: row.mode, template_id: row.template_id)
    published = row&.ia? && Rt::Routing::TemplateLookup.published?(account: conversation.account, template_id: row.template_id) == true
    decision = Rt::Routing::Resolver.call(status: conversation.status, team_id: conversation.team_id, assignee_id: conversation.assignee_id,
                                          entry_team_id: entry&.team_id, binding: binding, agent_published: published)
    team = team_id && conversation.account.teams.find_by(id: team_id)
    { routing_mode: mode, respondent: decision[:respondent], reason: decision[:reason], queue_id: team_id, queue_name: team&.name,
      assignee_name: conversation.assignee&.available_name }
  end
end
