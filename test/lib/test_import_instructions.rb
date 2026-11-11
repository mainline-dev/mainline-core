# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/import_instructions'
require_relative '../../lib/mainline_file'

describe ImportInstructions do
  cover 'ImportInstructions*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
  end

  def json_blocks(text)
    text.scan(/```json\n(.*?)```/m).flatten.map { |block| JSON.parse(block) }
  end

  it 'carries the schema, whole and unchanged' do
    schema = JSON.parse(File.read(MainlineFile::SCHEMA_PATH))

    assert_includes json_blocks(ImportInstructions.for(team_id: nil)), schema
  end

  it 'shows an example that Mainline itself would accept' do
    example = json_blocks(ImportInstructions.for(team_id: nil)).find { |block| block['mainline'] }
    read = MainlineFile.read(JSON.generate(example))

    assert_predicate read, :success?, read.errors.inspect
    refute_nil read.backbone
    refute_empty read.items.first[:suggested]['scenarios']
  end

  it "lists the activities and steps on the team's maps, so suggestions can name them" do
    map = Map.create(team_id: @team.id, name: 'RepoBoard', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Track work', position: 1000)
    Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Change an item', position: 1000)
    Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Gone', position: 2000, archived_at: Time.now)

    text = ImportInstructions.for(team_id: @team.id)

    assert_includes text, 'RepoBoard'
    assert_includes text, 'Track work: Change an item'
    refute_includes text, 'Gone'
  end

  it 'says nothing of maps when there is no team, or the team has none' do
    assert_equal ImportInstructions.for(team_id: nil), ImportInstructions.for(team_id: @team.id)
  end

  it "leaves another team's maps out" do
    other = Team.create(name: 'Other')
    SetTeamContext.call(other.id)
    Map.create(team_id: other.id, name: 'Secret plans', position: 1000)
    SetTeamContext.call(@team.id)

    refute_includes ImportInstructions.for(team_id: @team.id), 'Secret plans'
  end
end
