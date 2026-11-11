# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/bypass_rls'
require_relative '../../lib/data_export'
require_relative '../../lib/map_order'

# An export reads through the database role the app uses, so even code asked
# for another team's export finds none of that team's work.
describe 'Team export row level security' do
  before do
    @theirs = Team.create(name: 'Theirs')
    SetTeamContext.call(@theirs.id)
    person = Person.create(name: 'Theirs', email: 'someone@theirs.co')
    map = Map.create(team_id: @theirs.id, name: 'Their map', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @theirs.id, name: 'Sign up', position: 1000)
    task = Task.create(map_id: map.id, team_id: @theirs.id, activity_id: activity.id, name: 'Register', position: 1000)
    Story.create(map_id: map.id, team_id: @theirs.id, task_id: task.id, title: 'Secret plan', position: 1000,
      created_by_id: person.id)
    MuseumItem.create(team_id: @theirs.id, source_key: 'PROJ-1', issue_type: 'Story', summary: 'Secret ticket')

    SetTeamContext.call(Team.create(name: 'Mine').id)
  end

  it "lists none of another team's stories" do
    assert_empty MapOrder.for(@theirs.id)
  end

  it "holds none of another team's record" do
    record = DataExport.export(@theirs.id)

    %i[maps activities steps stories personas release_slices museum_items events].each do |part|
      assert_empty record[part], part.to_s
    end
  end
end
