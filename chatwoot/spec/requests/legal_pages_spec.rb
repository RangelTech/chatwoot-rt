require 'rails_helper'

RSpec.describe 'Páginas legais RAtende', type: :request do
  it 'expõe a política no domínio do Chatwoot sem autenticação' do
    get '/politica-de-privacidade'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Política de Privacidade', 'RAtende')
  end

  it 'expõe termos e instruções de exclusão de dados' do
    get '/termos-de-servico'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Termos de Serviço')

    get '/exclusao-de-dados'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Solicitação de exclusão de dados')
  end
end
