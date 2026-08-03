# Deixa o painel em português para quem já tem conta.
#
# `DEFAULT_LOCALE=pt_BR` só decide o idioma de conta NOVA: conta que já existe
# guarda o idioma escolhido no cadastro, e as nossas nasceram em inglês. Sem
# este passo, o cliente entra e vê "Account Settings" no primeiro login — que é
# exatamente o que a variável parecia resolver.
#
# Idempotente de propósito: roda a cada deploy sem efeito quando já está certo.
#
# Uso: bundle exec rails runner scripts/ops/locale_pt_br.rb

alvo = 'pt_BR'
mudadas = Account.where.not(locale: alvo).count
Account.where.not(locale: alvo).find_each { |conta| conta.update!(locale: alvo) }
puts "contas em #{alvo}: #{Account.where(locale: alvo).count} (#{mudadas} alteradas)"
