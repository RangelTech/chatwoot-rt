# Recebe o resultado do ensaio semanal de mesclagem (workflow do repositório). Autenticado por token
# compartilhado (RT_UPGRADE_REPORT_TOKEN); sem o token configurado o endpoint responde 404.
class Rt::UpgradeRehearsalsController < ActionController::API
  STATUSES = %w[clean conflicts error].freeze

  def create
    expected = ENV['RT_UPGRADE_REPORT_TOKEN'].to_s
    return head :not_found if expected.blank?
    return head :unauthorized unless authorized?(expected)

    status = params[:status].to_s
    return render json: { error: 'status invalido' }, status: :unprocessable_entity unless STATUSES.include?(status)

    entry = Rt::UpgradeStatus.record_rehearsal(
      target: params[:target], status: status, conflicts: params[:conflicts], files: params[:files],
      summary_url: params[:summary_url]
    )
    render json: entry, status: :created
  end

  private

  def authorized?(expected)
    given = request.authorization.to_s.delete_prefix('Bearer ')
    ActiveSupport::SecurityUtils.secure_compare(given, expected)
  end
end
