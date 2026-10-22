require 'rails_helper'

# F-2: matriz completa fila x responsavel x status x modo x agente publicado.
RSpec.describe Rt::Routing::Resolver do
  def ia(mode: 'piloto')
    described_class::QueueInfo.new(respondent_kind: 'ia', mode: mode, template_id: 'tpl-1')
  end

  def humano
    described_class::QueueInfo.new(respondent_kind: 'humano', mode: 'desligado', template_id: nil)
  end

  def run(**args)
    described_class.call(**{ status: 'open' }.merge(args))
  end

  describe 'matriz (status x fila x responsavel x modo x publicado)' do
    statuses = %w[open pending snoozed]
    kinds = { 'sem_vinculo' => nil, 'humano' => :humano, 'ia_piloto' => :ia, 'ia_desligado' => :ia_off }
    kinds.each do |kind_name, kind|
      [nil, 7].each do |assignee|
        [true, false].each do |published|
          statuses.each do |status|
            it "status=#{status} fila=#{kind_name} responsavel=#{assignee.inspect} publicado=#{published}" do
              binding_info = { nil => nil, humano: humano, ia: ia, ia_off: ia(mode: 'desligado') }[kind]
              result = run(status: status, team_id: 1, assignee_id: assignee, binding: binding_info, agent_published: published)
              expected = if assignee then 'humano'
                         elsif kind == :ia && published then 'ia'
                         else 'humano'
                         end
              expect(result[:respondent]).to eq(expected)
              expect(result[:queue_id]).to eq(1)
            end
          end
        end
      end
    end
  end

  it 'resolvida => ninguem, em qualquer combinacao' do
    [nil, 1].product([nil, 7], [nil, humano, ia]).each do |team, assignee, queue|
      result = run(status: 'resolved', team_id: team, assignee_id: assignee, binding: queue, agent_published: true, entry_team_id: 9)
      expect(result[:respondent]).to eq('ninguem')
    end
  end

  describe 'sem fila' do
    it 'aplica a fila de entrada e reavalia (IA)' do
      result = run(team_id: nil, entry_team_id: 5, binding: ia, agent_published: true)
      expect(result).to include(respondent: 'ia', queue_id: 5, apply_entry_queue: true, agent: 'tpl-1')
    end

    it 'fila de entrada humana => humano' do
      result = run(team_id: nil, entry_team_id: 5, binding: humano)
      expect(result).to include(respondent: 'humano', queue_id: 5, apply_entry_queue: true, reason: 'fila_humana')
    end

    it 'sem fila de entrada => humano e nada a aplicar' do
      expect(run(team_id: nil)).to include(respondent: 'humano', reason: 'sem_fila', apply_entry_queue: false)
    end

    it 'responsavel humano vence a fila de entrada' do
      expect(run(team_id: nil, assignee_id: 3, entry_team_id: 5, binding: ia, agent_published: true))
        .to include(respondent: 'humano', reason: 'responsavel_humano')
    end
  end

  it 'explica o motivo quando a fila de IA nao responde' do
    expect(run(team_id: 1, binding: ia(mode: 'desligado'), agent_published: true)[:reason]).to eq('modo_desligado')
    expect(run(team_id: 1, binding: ia, agent_published: false)[:reason]).to eq('agente_nao_publicado')
  end

  it 'e pura: nao altera os argumentos e repete o resultado' do
    queue = ia
    a = run(team_id: 1, binding: queue, agent_published: true)
    b = run(team_id: 1, binding: queue, agent_published: true)
    expect(a).to eq(b)
  end
end
