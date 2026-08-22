class ApiController < ApplicationController
  skip_before_action :set_current_user, only: [:index]

  def index
    render json: { version: Chatwoot.config[:version],
                   timestamp: Time.now.utc.to_fs(:db),
                   queue_services: redis_status,
                   data_services: postgres_status }
  end

  private

  def redis_status
    r = Redis.new(Redis::Config.app)
    return 'ok' if r.ping
  rescue Redis::CannotConnectError
    'failing'
  end

  def postgres_status
    # Rails opens database connections lazily. `active?` therefore returns
    # false on a perfectly healthy idle web process, producing a misleading
    # public health status. A tiny read is the actual dependency probe.
    ActiveRecord::Base.connection.select_value('SELECT 1') == 1 ? 'ok' : 'failing'
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
    'failing'
  end
end
