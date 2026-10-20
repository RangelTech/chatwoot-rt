# Fase F (F-1): TeamMember nao pode ser criado em fila de IA (cobre UI, API, Super Admin e console).
module Rt::TeamMemberAiQueueGuard
  extend ActiveSupport::Concern

  prepended do
    validate :rt_team_is_not_ai_queue, on: :create
  end

  private

  def rt_team_is_not_ai_queue
    errors.add(:team, 'AI-managed queue cannot have human members') if team_id && Rt::QueueBinding.ia.exists?(team_id: team_id)
  end
end
