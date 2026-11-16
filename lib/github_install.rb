# frozen_string_literal: true

require 'rack/utils'
require 'securerandom'
require_relative 'ci_monitor'

# Linking a team to an installation of the CI Monitor's GitHub App. GitHub
# sends the person back with an installation number anyone could type in, so
# an installation is linked only when GitHub's own list of the installations
# the person can see includes it, and only for the install this session
# started.
module GithubInstall
  TOKEN_TTL = 3600
  STARTED = 'github_install'

  # Starts an install for the team, and gives the state GitHub's link carries.
  def self.start(session, team_id)
    state = SecureRandom.urlsafe_base64(32)
    session[STARTED] = { 'state' => state, 'team_id' => team_id }
    state
  end

  # The team of the install this session started, when the state GitHub sent
  # back is that install's. An install finishes once, whatever the answer.
  def self.finish(session, state)
    started = session.delete(STARTED)
    started['team_id'] if started && Rack::Utils.secure_compare(started['state'], state.to_s)
  end

  # The person's GitHub sign-in for the CI Monitor, while it lasts.
  def self.token(session, now: Time.now)
    token = session['ci_monitor_token']
    return token if token && now.to_i - session['ci_monitor_token_at'].to_i <= TOKEN_TTL

    session.delete('ci_monitor_token')
    session.delete('ci_monitor_token_at')
    nil
  end

  # The installation as GitHub lists it for the person, for this app, or nil.
  def self.seen(token, installation_id, app_id: ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i)
    CIMonitor::GithubAPI.user_installations(token).find { |i| i[:app_id] == app_id && i[:id] == installation_id }
  end

  def self.link(team_id, installation)
    return if TeamInstallation.where(team_id: team_id, provider: 'github', installation_id: installation[:id]).any?

    TeamInstallation.create(team_id: team_id, provider: 'github', installation_id: installation[:id],
      org_name: installation[:account_login])
  end
end
