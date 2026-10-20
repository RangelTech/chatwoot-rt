# Fase F-4: traz a configuracao que ainda vive na bridge para as tabelas Rt do
# Chatwoot. A bridge continua sendo a fonte do legado ate o rollout; por isso a
# operacao e explicita, idempotente e guarda o retrato necessario para voltar.
class Rt::Routing::LegacyMigration
  LEGACY_HUMAN_STATES = %w[human_queue human_active].freeze

  def self.apply(account:, configurations:, conversations: [])
    new(account: account, configurations: configurations, conversations: conversations).apply
  end

  def self.rollback(account:, inbox_id:)
    new(account: account, configurations: [], conversations: []).rollback(inbox_id)
  end

  def initialize(account:, configurations:, conversations:)
    @account = account
    @configurations = Array(configurations)
    @conversations = Array(conversations)
  end

  def apply
    result = { inboxes: 0, conversations_migrated: 0, conversations_skipped: 0 }
    @configurations.each do |raw|
      config = raw.to_h.stringify_keys
      inbox = @account.inboxes.find_by(id: config.fetch('inbox_id'))
      raise ArgumentError, "caixa #{config['inbox_id']} nao pertence a conta" unless inbox

      ai_team = find_team(config.fetch('ai_team_id'), 'fila de IA')
      handoff_team = find_team(config['handoff_team_id'], 'fila de repasse', required: false)
      assert_ai_team_safe!(ai_team)

      entry = Rt::InboxEntryQueue.find_or_initialize_by(inbox: inbox)
      snapshot = entry.legacy_snapshot.deep_dup
      snapshot['legacy_bridge_config'] ||= config.slice('inbox_id', 'ai_team_id', 'handoff_team_id', 'template_id', 'autopilot')
      snapshot['teams'] ||= {}
      snapshot['teams'][ai_team.id.to_s] ||= { 'allow_auto_assign' => ai_team.allow_auto_assign }
      snapshot['conversation_teams'] ||= {}

      # A flag do time faz parte do estado antigo e e restaurada pelo rollback.
      ai_team.update!(allow_auto_assign: false) if ai_team.allow_auto_assign
      binding = Rt::QueueBinding.find_or_initialize_by(team: ai_team)
      binding.assign_attributes(
        account: @account,
        respondent_kind: 'ia',
        template_id: config.fetch('template_id').to_s,
        mode: config['autopilot'] == false ? 'desligado' : 'piloto',
        allowed_destination_team_ids: handoff_team ? [handoff_team.id] : []
      )
      binding.save!

      entry.assign_attributes(account: @account, team: ai_team, routing_mode: 'sombra', legacy_snapshot: snapshot)
      entry.save!
      result[:inboxes] += 1
      migrate_conversations!(inbox, ai_team, handoff_team, entry, result)
    end
    result
  end

  # A volta nunca apaga registros Rt: desliga o modo novo, restaura as filas
  # das conversas e conserva a trilha de auditoria para uma nova tentativa.
  def rollback(inbox_id)
    inbox = @account.inboxes.find_by(id: inbox_id)
    raise ArgumentError, "caixa #{inbox_id} nao pertence a conta" unless inbox

    entry = Rt::InboxEntryQueue.find_by!(inbox: inbox)
    snapshot = entry.legacy_snapshot || {}
    restored = 0
    (snapshot['conversation_teams'] || {}).each do |conversation_id, team_id|
      conversation = @account.conversations.find_by(id: conversation_id)
      next unless conversation

      conversation.update!(team_id: team_id)
      restored += 1
    end

    (snapshot['teams'] || {}).each do |team_id, state|
      binding = Rt::QueueBinding.find_by(team_id: team_id)
      # Sem apagar o binding, ele deixa de ser uma fila de IA antes de a flag
      # antiga do Team ser restaurada. Isso mantem todos os dados recuperaveis.
      binding&.update_columns(respondent_kind: 'humano', template_id: nil, mode: 'desligado')
      team = @account.teams.find_by(id: team_id)
      team&.update_column(:allow_auto_assign, state['allow_auto_assign'])
    end

    entry.update!(routing_mode: 'legado')
    { inbox_id: inbox.id, conversations_restored: restored }
  end

  private

  def find_team(id, label, required: true)
    return nil if id.blank? && !required

    team = @account.teams.find_by(id: id)
    raise ArgumentError, "#{label} #{id} nao pertence a conta" unless team

    team
  end

  def assert_ai_team_safe!(team)
    return unless team.team_members.exists?

    raise ArgumentError, "fila de IA #{team.id} possui membros humanos; corrija antes da migracao"
  end

  def migrate_conversations!(inbox, ai_team, handoff_team, entry, result)
    @conversations.each do |raw|
      state = raw.to_h.stringify_keys
      conversation = @account.conversations.find_by(id: state['conversation_id']) ||
                     @account.conversations.find_by(display_id: state['conversation_id'])
      next unless conversation&.inbox_id == inbox.id
      next if conversation.status == 'resolved'

      destination = LEGACY_HUMAN_STATES.include?(state['state']) ? handoff_team : ai_team
      unless destination
        result[:conversations_skipped] += 1
        next
      end

      snapshot = entry.legacy_snapshot.deep_dup
      snapshot['conversation_teams'] ||= {}
      snapshot['conversation_teams'][conversation.id.to_s] ||= conversation.team_id
      entry.update!(legacy_snapshot: snapshot) if entry.legacy_snapshot != snapshot
      next if conversation.team_id == destination.id

      conversation.update!(team_id: destination.id)
      result[:conversations_migrated] += 1
    end
  end
end
