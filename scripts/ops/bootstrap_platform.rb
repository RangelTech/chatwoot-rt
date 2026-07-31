# Bootstrap operacional do Chatwoot: super admin + platform app da ponte.
#
# Idempotente: rodar de novo não duplica nada e devolve o mesmo token.
# Uso (Cloud Run job): bundle exec rails runner scripts/ops/bootstrap_platform.rb
#
# Variáveis esperadas:
#   RT_SUPER_ADMIN_EMAIL / RT_SUPER_ADMIN_PASSWORD  — acesso administrativo
#   RT_PLATFORM_APP_NAME                            — nome do app da ponte

email = ENV.fetch('RT_SUPER_ADMIN_EMAIL')
password = ENV.fetch('RT_SUPER_ADMIN_PASSWORD')
app_name = ENV.fetch('RT_PLATFORM_APP_NAME', 'rangel-bridge')

admin = SuperAdmin.find_by(email: email)
if admin.nil?
  admin = SuperAdmin.create!(
    name: ENV.fetch('RT_SUPER_ADMIN_NAME', 'Rangel Tech'),
    email: email,
    password: password,
    password_confirmation: password
  )
  puts "super_admin_created=#{admin.email}"
else
  puts "super_admin_exists=#{admin.email}"
end

app = PlatformApp.find_by(name: app_name)
if app.nil?
  app = PlatformApp.create!(name: app_name)
  puts "platform_app_created=#{app.name}"
else
  puts "platform_app_exists=#{app.name}"
end

# É este token que a ponte usa na Platform API para criar contas, espelhar
# usuários e gerar os links de SSO.
puts "PLATFORM_TOKEN=#{app.access_token.token}"
