#!/bin/sh
# Worker Sidekiq: e-mails, automações, jobs de conversa.
#
# Roda com min-instances=1 porque fila parada é atendimento parado — sem o
# worker, mensagens ficam presas sem ninguém perceber.
#
# O Cloud Run exige que o container escute em $PORT, e o Sidekiq não escuta
# nada. Por isso subimos um respondedor HTTP mínimo em background, só para o
# health check, e deixamos o Sidekiq em primeiro plano: se ele morrer, o
# container morre junto e o Cloud Run reinicia — que é o comportamento certo
# para um worker.
set -eu

: "${PORT:=8080}"

ruby -rsocket -e '
  server = TCPServer.new("0.0.0.0", ENV.fetch("PORT", "8080").to_i)
  loop do
    begin
      socket = server.accept
      socket.gets
      socket.print("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\nok")
      socket.close
    rescue StandardError
      next
    end
  end
' &

exec bundle exec sidekiq -C config/sidekiq.yml
