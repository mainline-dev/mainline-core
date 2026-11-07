# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/delete_team'

describe 'CI Monitor rows when a team is deleted' do
  before do
    @team = Team.create(name: 'Doomed')
    SetTeamContext.call(@team.id)
    TeamInstallation.create(team_id: @team.id, provider: 'github', installation_id: 55_555)
    @repo = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 55_555, provider_repo_id: 9001,
      repo_name: 'doomed/platform', default_branch: 'main', threshold_hours: 24, last_push_at: Time.now
    )
    branch = TrackedBranch.create(monitored_repo_id: @repo.id, branch_name: 'feature/x', status: 'open')
    IntegrationEvent.create(monitored_repo_id: @repo.id, event_type: 'push', occurred_at: Time.now, tracked_branch_id: branch.id)
  end

  it 'deletes the installation, repos, branches and integration events with the team' do
    DeleteTeam.call(team: @team)

    assert_equal 0, TeamInstallation.where(team_id: @team.id).count
    assert_equal 0, MonitoredRepo.where(team_id: @team.id).count
    assert_equal 0, TrackedBranch.where(monitored_repo_id: @repo.id).count
    assert_equal 0, IntegrationEvent.where(monitored_repo_id: @repo.id).count
  end
end
