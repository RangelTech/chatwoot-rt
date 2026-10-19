class Api::V1::Accounts::RtAi::MeController < Api::V1::Accounts::RtAi::BaseController
  def show
    engine = engine_get('/internal/ui/me')
    return if engine.nil?

    render json: { account_id: Current.account.id, scopes: engine['scopes'], flags: engine['flags'] }
  end
end
