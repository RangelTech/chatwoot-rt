# Fase F (F-1): liga uma fila (Team) a um respondente. Fila de IA ("Gerenciada por IA") nao tem membros humanos.
class Rt::QueueBinding < ApplicationRecord
  self.table_name = 'rt_queue_bindings'

  KINDS = %w[humano ia].freeze
  MODES = %w[piloto desligado].freeze

  belongs_to :account
  belongs_to :team

  scope :ia, -> { where(respondent_kind: 'ia') }

  validates :respondent_kind, inclusion: { in: KINDS }
  validates :mode, inclusion: { in: MODES }
  validates :team_id, uniqueness: true
  validate :team_belongs_to_account
  validate :ai_queue_rules, if: :ia?
  validate :destinations_in_account

  before_validation :clear_ai_fields, unless: :ia?

  def ia?
    respondent_kind == 'ia'
  end

  def humano?
    respondent_kind == 'humano'
  end

  def autopilot?
    mode == 'piloto'
  end

  private

  def team_belongs_to_account
    errors.add(:team, 'must belong to the account') if team && team.account_id != account_id
  end

  def ai_queue_rules
    errors.add(:team, 'AI-managed queue cannot have human members') if team&.team_members&.exists?
    errors.add(:team, 'AI-managed queue cannot use auto assignment') if team&.allow_auto_assign
    errors.add(:template_id, 'is required') if template_id.blank?
    return if template_id.blank?

    published = Rt::Routing::TemplateLookup.published?(account: account, template_id: template_id)
    errors.add(:template_id, 'must be a published agent of this account') if published == false
  end

  def clear_ai_fields
    self.template_id = nil
    self.mode = 'desligado'
  end

  def destinations_in_account
    ids = Array(allowed_destination_team_ids).map(&:to_i).uniq
    return if ids.empty?

    errors.add(:allowed_destination_team_ids, 'must be teams of the account') if account.teams.where(id: ids).count != ids.size
    errors.add(:allowed_destination_team_ids, 'cannot include the queue itself') if ids.include?(team_id)
  end
end
