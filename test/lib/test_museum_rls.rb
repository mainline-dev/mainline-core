# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/bypass_rls'

# Ticket Museum items are isolated by team like the rest of a team's work.
describe 'Ticket Museum row level security' do
  before do
    @team = Team.create(name: 'RLS Test')
    SetTeamContext.call(@team.id)
  end

  it 'isolates museum items by team' do
    MuseumItem.create(team_id: @team.id, source_key: 'PROJ-1', issue_type: 'Story', summary: 'Secret plan')

    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)

    assert_empty MuseumItem.all
  end

  it 'isolates museum imports by team' do
    person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    MuseumImport.create(team_id: @team.id, actor_id: person.actor_id, file_name: 'secret.csv', status: 'staged')

    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)

    assert_empty MuseumImport.all
  end
end
