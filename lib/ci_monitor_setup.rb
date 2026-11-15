# frozen_string_literal: true

# Whether this install runs the CI Monitor. It needs a GitHub App of the
# install's own, held in six settings. An install without one sets all six to
# "disabled": the CI Monitor page then says it is not set up on this server
# and GitHub's webhook has no address. Some but not all disabled is a mistake,
# and the app refuses to start.
module CIMonitorSetup
  SETTINGS = %w[
    CI_MONITOR_GITHUB_APP_ID CI_MONITOR_GITHUB_APP_SLUG CI_MONITOR_GITHUB_APP_CLIENT_ID
    CI_MONITOR_GITHUB_APP_CLIENT_SECRET CI_MONITOR_GITHUB_PRIVATE_KEY CI_MONITOR_GITHUB_WEBHOOK_SECRET
  ].freeze
  OFF = 'disabled'

  def self.on?(env = ENV)
    SETTINGS.none? { |name| env[name] == OFF }
  end

  # The settings still set when some, but not all, are disabled.
  def self.half_off(env = ENV)
    off, set = SETTINGS.partition { |name| env[name] == OFF }
    off.empty? ? [] : set
  end
end
