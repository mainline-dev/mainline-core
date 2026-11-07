# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/bypass_rls'

# CI Monitor tables are isolated by team like core's, and readable across
# teams only inside BypassRLS.
describe 'CI Monitor row level security' do
  before do
    @team = Team.create(name: 'RLS Test')
    SetTeamContext.call(@team.id)
  end

  it 'isolates tracked branches by team' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 1,
      provider_repo_id:         100,
      repo_name:                'acme/app',
      default_branch:           'main'
    )
    TrackedBranch.create(monitored_repo_id: repo.id, branch_name: 'feature/secret', status: 'open')

    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)

    assert_empty TrackedBranch.all
  end

  it 'isolates team_installations by team' do
    TeamInstallation.create(
      team_id: @team.id, provider: 'github', installation_id: 55555
    )

    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)

    assert_empty TeamInstallation.all
  end
end
