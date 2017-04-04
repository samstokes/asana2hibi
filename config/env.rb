if ENV['RACK_ENV'] != 'production'
  require 'dotenv'
  Dotenv.load
end

ASANA_API_TOKEN = ENV.fetch('ASANA_API_TOKEN')
ASANA_WORKSPACE_ID = ENV.fetch('ASANA_WORKSPACE_ID')
asana_main_project_id = ENV['ASANA_MAIN_PROJECT_ID']
ASANA_MAIN_PROJECT_ID = asana_main_project_id ? Integer(asana_main_project_id) : nil
asana_main_project_section_id = ENV['ASANA_MAIN_PROJECT_SECTION_ID']
ASANA_MAIN_PROJECT_SECTION_ID = asana_main_project_section_id ? Integer(asana_main_project_section_id) : nil

HIBI_OPTS = {
  server: ENV.fetch('HIBI_SERVER'),
  user: ENV.fetch('HIBI_USER'),
  password: ENV.fetch('HIBI_PASSWORD'),
}

SENTRY_DSN = ENV['SENTRY_DSN']
