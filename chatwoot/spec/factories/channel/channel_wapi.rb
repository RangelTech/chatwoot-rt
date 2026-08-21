# frozen_string_literal: true

FactoryBot.define do
  factory :channel_wapi, class: 'Channel::Wapi' do
    project_id { SecureRandom.uuid }
    token { SecureRandom.hex(20) }
    account
    # Achado real (produto-05, RSpec rodado pela 1a vez 21/08/2026): `inbox`
    # sozinho builda o `:inbox` default, que tem SEU PRÓPRIO `account` --
    # sem thread explícita, `channel.account_id` e `inbox.account_id` ficam
    # em contas DIFERENTES sempre que `account:` é sobrescrito na chamada
    # (ex. `create(:channel_wapi, account: account)`). Isso nunca apareceu
    # no `channel_line` (mesmo padrão upstream) porque nenhum spec de lá
    # jamais sobrescreveu `account:`.
    inbox { association :inbox, account: account }
  end
end
