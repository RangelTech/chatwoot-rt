# Fase F (F-5): aplica o repasse pedido pela IA: nota privada com o resumo + atribuicao a outra fila,
# somente entre os destinos permitidos da fila de origem. Destino fora da lista: ignorado e registrado.
class Rt::Routing::Handoff
  Result = Struct.new(:ok, :reason, :team_id, keyword_init: true)

  def self.call(conversation:, destination: nil, summary: nil, run_id: nil)
    new(conversation, destination, summary, run_id).call
  end

  def initialize(conversation, destination, summary, run_id)
    @conversation = conversation
    @destination = destination
    @summary = summary.to_s.strip
    @run_id = run_id
  end

  def call
    origin = @conversation.team_id
    binding = origin && Rt::QueueBinding.find_by(team_id: origin)
    return refuse('sem_fila_de_origem') unless binding

    allowed = Array(binding.allowed_destination_team_ids)
    return refuse('sem_destinos_permitidos') if allowed.empty?

    target = pick_target(allowed)
    return refuse('destino_nao_permitido') unless target

    add_note if @summary.present?
    @conversation.update!(team_id: target.id)
    Rt::RoutingEvent.record!(conversation: @conversation, from_team_id: origin, to_team_id: target.id, actor_kind: 'ia',
                             reason: 'repasse_da_ia', run_id: @run_id)
    Result.new(ok: true, reason: 'repassado', team_id: target.id)
  end

  private

  # `destination` pode ser o id da fila, o nome ou nil (= primeira fila de repasse padrao da origem).
  def pick_target(allowed)
    teams = @conversation.account.teams.where(id: allowed)
    return teams.order(:id).first if @destination.blank?

    key = @destination.to_s.strip
    teams.find { |t| t.id.to_s == key || t.name.casecmp?(key) }
  end

  def add_note
    @conversation.messages.create!(
      account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing, private: true,
      content: "Resumo do repasse: #{@summary}", content_attributes: { rt_origin: 'ia', rt_kind: 'handoff_summary', run_id: @run_id }
    )
  end

  def refuse(reason)
    Rt::RoutingEvent.record!(conversation: @conversation, from_team_id: @conversation.team_id, to_team_id: nil, actor_kind: 'ia',
                             reason: "recusado:#{reason}", run_id: @run_id)
    Result.new(ok: false, reason: reason)
  end
end
