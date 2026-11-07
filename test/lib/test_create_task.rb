# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_task'

describe CreateTask do
  cover 'CreateTask*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
  end

  def create(name: 'Search', activity_id: @activity.id)
    CreateTask.call(map: @map, team: @team, actor: @person.actor, name: name, activity_id: activity_id)
  end

  it 'creates a task under the activity' do
    result = create

    assert_predicate result, :success?
    assert_empty result.errors
    assert_equal 'Search', result.task.name
    assert_equal @activity.id, result.task.activity_id
    assert_equal @map.id, result.task.map_id
    assert_equal @team.id, result.task.team_id
  end

  it 'places the task after the last task in the activity' do
    first = create(name: 'First').task
    second = create(name: 'Second').task

    assert_equal 1000, first.position
    assert_equal 2000, second.position
  end

  it 'records a created event' do
    task = create.task

    event = Event.where(entity_id: task.id, action: 'created').first

    assert_equal @person.actor_id, event.actor_id
    assert_equal({ 'name' => 'Search', 'activity_id' => @activity.id, 'position' => 1000 }, event.after_state)
  end

  it 'requires a name' do
    result = create(name: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal 0, Task.where(map_id: @map.id).count
  end

  it 'rejects a name over 100 characters' do
    assert_predicate create(name: 'x' * 100), :success?

    result = create(name: 'x' * 101)

    assert_equal 1, result.errors.size
  end

  it 'requires an activity' do
    result = create(activity_id: nil)

    assert_equal 1, result.errors.size
  end

  it 'rejects an activity that does not exist' do
    result = create(activity_id: SecureRandom.uuid)

    assert_equal 1, result.errors.size
  end

  it 'rejects an activity on another map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)
    other = Activity.create(map_id: other_map.id, team_id: @team.id, name: 'Elsewhere', position: 1000)

    result = create(activity_id: other.id)

    assert_equal 1, result.errors.size
  end

  it 'rejects an archived activity' do
    @activity.update(archived_at: Time.now)

    result = create

    assert_equal 1, result.errors.size
  end

  it 'reports every error at once' do
    result = create(name: nil, activity_id: nil)

    assert_equal 2, result.errors.size
  end
end
