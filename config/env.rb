if ENV['RACK_ENV'] != 'production'
  require 'dotenv'
  Dotenv.load
end

ASANA_API_TOKEN = ENV.fetch('ASANA_API_TOKEN')
ASANA_WORKSPACE_ID = ENV.fetch('ASANA_WORKSPACE_ID')

HIBI_OPTS = {
  server: ENV.fetch('HIBI_SERVER'),
  user: ENV.fetch('HIBI_USER'),
  password: ENV.fetch('HIBI_PASSWORD'),
}
