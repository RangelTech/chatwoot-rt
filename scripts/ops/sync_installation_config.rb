# Aplica no Chatwoot os segredos que a plataforma guarda no banco dela.
#
# `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN` e `IG_VERIFY_TOKEN` são
# `InstallationConfig` — linhas de banco, não só variável de ambiente. Escrevê-las
# aqui faz o canal do Instagram/Messenger valer sem redeploy, que é o ponto
# inteiro de tirar essas chaves do env.
#
# ATENÇÃO ao `GlobalConfigService.load`: ele faz `ENV.fetch(chave) { banco }`.
# **A variável de ambiente vence sobre o banco.** Enquanto o deploy injetar
# `FB_*` como env, o que está escrito aqui não tem efeito nenhum — e o sintoma
# seria "salvei a chave na tela e o Instagram continua sumido". Por isso o
# `deploy.sh` parou de injetá-las.
#
# Idempotente e sem eco: só escreve o que mudou, nunca toca config `locked`, e
# imprime apenas os nomes — nunca os valores.
#
# Uso:
#   PLATFORM_URL=... PLATFORM_SYNC_TOKEN=... \
#     bundle exec rails runner scripts/ops/sync_installation_config.rb

require 'net/http'
require 'json'

url = ENV.fetch('PLATFORM_URL', '').sub(%r{/\z}, '')
token = ENV.fetch('PLATFORM_SYNC_TOKEN', '')
abort('defina PLATFORM_URL e PLATFORM_SYNC_TOKEN') if url.empty? || token.empty?

uri = URI("#{url}/api/installation-secrets/for-chatwoot")
pedido = Net::HTTP::Get.new(uri)
pedido['Authorization'] = "Bearer #{token}"

resposta = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
  http.request(pedido)
end
abort("plataforma respondeu #{resposta.code}") unless resposta.code.to_i < 300

segredos = JSON.parse(resposta.body)
aplicados = []
ignorados = []

segredos.each do |nome, valor|
  config = InstallationConfig.find_or_initialize_by(name: nome)
  # `locked` existe para o operador do Chatwoot travar um valor à mão. Passar
  # por cima disso seria a plataforma decidindo por quem já decidiu.
  if config.persisted? && config.locked?
    ignorados << nome
    next
  end
  next if config.value == valor

  config.update!(value: valor)
  aplicados << nome
end

GlobalConfig.clear_cache

# Confirma o que de fato entrou. Sem este passo, "entreguei o valor" viraria
# sinônimo de "está valendo lá" — e a diferença entre as duas é exatamente onde
# mora a falha que ninguém percebe.
ack = URI("#{url}/api/installation-secrets/chatwoot-ack")
pedido_ack = Net::HTTP::Post.new(ack, 'Content-Type' => 'application/json')
pedido_ack['Authorization'] = "Bearer #{token}"
pedido_ack.body = JSON.dump({ 'applied' => aplicados, 'skipped' => ignorados })
Net::HTTP.start(ack.hostname, ack.port, use_ssl: ack.scheme == 'https') do |http|
  http.request(pedido_ack)
end

puts "aplicados: #{aplicados.sort.join(', ')}" unless aplicados.empty?
puts "ignorados (locked): #{ignorados.sort.join(', ')}" unless ignorados.empty?
puts "nada a fazer" if aplicados.empty? && ignorados.empty?
