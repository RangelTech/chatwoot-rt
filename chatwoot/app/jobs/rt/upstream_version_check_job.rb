# Diário: atualiza a "última versão estável do upstream" mostrada no cartão do Super Admin.
class Rt::UpstreamVersionCheckJob < ApplicationJob
  queue_as :low

  def perform
    Rt::UpstreamVersionCheck.call
  end
end
