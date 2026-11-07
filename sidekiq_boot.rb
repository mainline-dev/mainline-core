# frozen_string_literal: true

require_relative 'lib/env_check'
require 'sidekiq'

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL') }
end

require_relative 'models'
require_relative 'lib/bypass_rls'
require_relative 'lib/set_team_context'
require_relative 'lib/ci_monitor'
require_relative 'lib/jobs/clear_stale_uploads_job'
require_relative 'lib/jobs/let_go_job'
require_relative 'lib/jobs/remove_unverified_accounts_job'
