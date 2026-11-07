# frozen_string_literal: true

require 'sequel/core'

# Always connect as the restricted app role; there is no fallback to the
# owner. Migrations pass the owner URL in as the app URL (see Rakefile).
# Outside test mode the URLs are deleted from the environment so they are not
# passed on to subprocesses; database URLs may contain passwords.
database_url = lambda do |var|
  url = ENV.fetch(var, nil)
  abort "FATAL: required environment variable #{var} is missing or empty" if url.to_s.empty?
  url
end

DB = case ENV.fetch('RACK_ENV', nil)
     when 'test'
       Sequel.connect(database_url.call('TEST_APP_DATABASE_URL'), max_connections: 5)
     else
       url = database_url.call('MAINLINE_APP_DATABASE_URL')
       ENV.delete('MAINLINE_DATABASE_URL')
       ENV.delete('MAINLINE_APP_DATABASE_URL')
       Sequel.connect(url, max_connections: 5)
     end

DB.extension :connection_validator
DB.pool.connection_validation_timeout = -1
DB.extension :pg_json
DB.extension :pg_auto_parameterize if DB.adapter_scheme == :postgres && Sequel::Postgres::USES_PG
