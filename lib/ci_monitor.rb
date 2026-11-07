# frozen_string_literal: true

require_relative '../models/team_installation'
require_relative '../models/monitored_repo'
require_relative '../models/tracked_branch'
require_relative '../models/integration_event'
require_relative 'ci_monitor/branch_age'
require_relative 'ci_monitor/dashboard'
require_relative 'ci_monitor/github_api'
require_relative 'ci_monitor/github_webhook_handler'
require_relative 'ci_monitor/repo_backfill'
require_relative 'ci_monitor/status'
require_relative 'ci_monitor/streak_strip'
require_relative 'ci_monitor/jobs/repo_backfill_job'

module CIMonitor
  # Clears a team's repos, branches, events and GitHub installations.
  def self.delete_team_data(team_id)
    repo_ids = MonitoredRepo.where(team_id: team_id).select(:id)
    IntegrationEvent.where(monitored_repo_id: repo_ids).delete
    TrackedBranch.where(monitored_repo_id: repo_ids).delete
    MonitoredRepo.where(team_id: team_id).delete
    TeamInstallation.where(team_id: team_id).delete
  end
end
