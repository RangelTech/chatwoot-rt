# Fase F-4: chamada somente pela bridge, autenticada pelo token interno.
class RtInternal::RoutingMigrationsController < ActionController::API
  before_action :authenticate_service

  def create
    account = Account.find_by(id: params[:account_id])
    return render json: { error: 'not_found' }, status: :not_found unless account

    result = Rt::Routing::LegacyMigration.apply(
      account: account,
      configurations: Array(params[:configurations]),
      conversations: Array(params[:conversations])
    )
    render json: result
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { error: 'migration_rejected', detail: e.message }, status: :unprocessable_entity
  end

  def rollback
    account = Account.find_by(id: params[:account_id])
    return render json: { error: 'not_found' }, status: :not_found unless account

    render json: Rt::Routing::LegacyMigration.rollback(account: account, inbox_id: params.require(:inbox_id))
  rescue ActiveRecord::RecordNotFound, ActionController::ParameterMissing, ArgumentError => e
    render json: { error: 'rollback_rejected', detail: e.message }, status: :unprocessable_entity
  end

  private

  def authenticate_service
    expected = ENV['RT_INTERNAL_TOKEN'].to_s
    given = request.headers['Authorization'].to_s.delete_prefix('Bearer ').strip
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    render json: { error: 'unauthorized' }, status: :unauthorized
  end
end
