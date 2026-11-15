# frozen_string_literal: true

require_relative 'ci_monitor_setup'

# What a team has connected beyond the map, in the order its page offers
# them: its Jira backlog in the Ticket Museum, GitHub for the CI Monitor, the
# deploy webhook for its pipeline, and a coding agent over MCP. GitHub is left
# out on an install without the CI Monitor.
module Activation
  def self.for(team, ci_monitor: CIMonitorSetup.on?)
    steps = {
      museum:  MuseumItem.where(team_id: team.id).exclude(source: 'mainline').any?,
      github:  TeamInstallation.where(team_id: team.id).any?,
      webhook: !team.webhook_token.nil?,
      agent:   !team.mcp_token.nil?
    }
    ci_monitor ? steps : steps.except(:github)
  end
end
