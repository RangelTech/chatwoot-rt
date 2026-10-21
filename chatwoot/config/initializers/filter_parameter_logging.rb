# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes
]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]

# Fase CH: assistente "Conectar canal" -- senha, código 2FA/verificação e o envelope `data`
# do passo de login nunca vão para log (casamento exato da chave, não por substring).
Rails.application.config.filter_parameters += [/\A(data|code|verification_code|password|webhook_secret)\z/i]
