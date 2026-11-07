# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/data_export'
require_relative '../../lib/record_event'

describe DataExport do
  cover 'DataExport*'
  before do
    @team = Team.create(name: 'Export Team')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@export.co')
    TeamMembership.create(team_id: @team.id, person_id: @person.id, working: true)
    @map = Map.create(team_id: @team.id, name: 'Product', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Onboarding', position: 1000)
    @task = Task.create(map_id: @map.id, team_id: @team.id, activity_id: @activity.id, name: 'Sign up', position: 1000)
    @story = Story.create(map_id: @map.id, team_id: @team.id, task_id: @task.id, title: 'Register', position: 1000,
      created_by_id: @person.id)
  end

  it 'exports team data as a hash' do
    result = DataExport.call(team_id: @team.id)

    assert_kind_of Hash, result
    assert_equal 'Export Team', result[:team][:name]
  end

  it 'includes maps' do
    result = DataExport.call(team_id: @team.id)

    assert_equal 1, result[:maps].length
    assert_equal 'Product', result[:maps].first[:name]
  end

  it 'includes activities, tasks, and stories' do
    result = DataExport.call(team_id: @team.id)

    assert_equal 1, result[:activities].length
    assert_equal 1, result[:tasks].length
    assert_equal 1, result[:stories].length
    assert_equal 'Register', result[:stories].first[:title]
  end

  it 'includes members' do
    result = DataExport.call(team_id: @team.id)

    assert_equal 1, result[:members].length
    assert_equal 'Alice', result[:members].first[:name]
  end

  it 'includes events' do
    RecordEvent.call(
      actor_id:    @person.actor_id,
      entity:      @story,
      action:      'created',
      after_state: { title: 'Register' }
    )

    result = DataExport.call(team_id: @team.id)

    assert_operator result[:events].length, :>=, 1
    assert_equal 'created', result[:events].first[:action]
    assert_equal 'story', result[:events].first[:entity_type]
  end

  it 'exports team fields' do
    result = DataExport.call(team_id: @team.id)
    t = result[:team]

    assert_equal %i[id name created_at], t.keys
    assert_equal @team.id, t[:id]
    refute_nil t[:created_at]
  end

  it 'exports map fields' do
    result = DataExport.call(team_id: @team.id)
    m = result[:maps].first

    assert_equal @map.id, m[:id]
    assert_equal 1000, m[:position]
    assert_nil m[:archived_at]
  end

  it 'exports activity fields' do
    result = DataExport.call(team_id: @team.id)
    a = result[:activities].first

    assert_equal @activity.id, a[:id]
    assert_equal @map.id, a[:map_id]
    assert_equal 'Onboarding', a[:name]
    assert_equal 1000, a[:position]
    assert_nil a[:archived_at]
  end

  it 'exports task fields' do
    result = DataExport.call(team_id: @team.id)
    t = result[:tasks].first

    assert_equal @task.id, t[:id]
    assert_equal @map.id, t[:map_id]
    assert_equal @activity.id, t[:activity_id]
    assert_equal 'Sign up', t[:name]
    assert_equal 1000, t[:position]
    assert_nil t[:archived_at]
  end

  it 'exports story fields with assignments' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    result = DataExport.call(team_id: @team.id)
    s = result[:stories].first

    assert_equal @story.id, s[:id]
    assert_equal @map.id, s[:map_id]
    assert_equal @task.id, s[:task_id]
    assert_equal 'Register', s[:title]
    assert_equal 'planned', s[:status]
    assert_equal 1000, s[:position]
    assert_nil s[:archived_at]
    assert_nil s[:release_slice_id]
    assert_equal 1, s[:assignments].length
    assert_equal @person.id, s[:assignments].first[:person_id]
    refute_nil s[:assignments].first[:assigned_at]
  end

  it 'exports persona fields' do
    persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Customer', position: 1000)

    result = DataExport.call(team_id: @team.id)
    p = result[:personas].find { |pr| pr[:id] == persona.id }

    refute_nil p
    assert_equal @map.id, p[:map_id]
    assert_equal 'Customer', p[:name]
    assert_equal 1000, p[:position]
    assert_nil p[:archived_at]
  end

  it 'exports release_slice fields' do
    slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)

    result = DataExport.call(team_id: @team.id)
    rs = result[:release_slices].first

    assert_equal slice.id, rs[:id]
    assert_equal @map.id, rs[:map_id]
    assert_equal 'MVP', rs[:name]
    assert_equal 1000, rs[:position]
    assert_nil rs[:archived_at]
  end

  it 'exports event fields with normalized entity type' do
    RecordEvent.call(
      actor_id: @person.actor_id, entity: @story,
      action: 'created', after_state: { title: 'Register' }
    )

    result = DataExport.call(team_id: @team.id)
    e = result[:events].first

    assert_equal @map.id, e[:map_id]
    assert_equal @person.actor_id, e[:actor_id]
    assert_equal 'story', e[:entity_type]
    assert_equal @story.id, e[:entity_id]
    assert_equal 'created', e[:action]
    refute_nil e[:occurred_at]
    refute_nil e[:before_state]
    refute_nil e[:after_state]
  end

  it 'exports member fields' do
    result = DataExport.call(team_id: @team.id)
    m = result[:members].first

    assert_equal @person.id, m[:person_id]
    assert_equal 'Alice', m[:name]
    assert m[:working]
    assert_nil m[:left_at]
  end

  it 'returns empty arrays for team with no maps' do
    empty_team = Team.create(name: 'Empty')
    SetTeamContext.call(empty_team.id)

    result = DataExport.call(team_id: empty_team.id)

    assert_empty result[:maps]
    assert_empty result[:activities]
    assert_empty result[:tasks]
    assert_empty result[:stories]
    assert_empty result[:personas]
    assert_empty result[:release_slices]
  end

  it 'returns valid JSON' do
    json = DataExport.to_json(team_id: @team.id)

    parsed = JSON.parse(json)

    assert_equal 'Export Team', parsed['team']['name']
  end
end
