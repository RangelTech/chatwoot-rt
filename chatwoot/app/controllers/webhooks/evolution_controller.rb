class Webhooks::EvolutionController < ActionController::API
  before_action :ensure_valid_channel

  def process_payload
    Webhooks::EvolutionEventsJob.perform_later(instance_name: params[:instance_name], params: params.to_unsafe_hash)
    head :ok
  end

  private

  def ensure_valid_channel
    return head :not_found unless channel
    return head :unauthorized unless provided_token.present? && ActiveSupport::SecurityUtils.secure_compare(provided_token, channel.webhook_verify_token)
  end

  def channel = @channel ||= Channel::EvolutionApi.find_by(instance_name: params[:instance_name])
  def provided_token = params[:verify_token].to_s
end
