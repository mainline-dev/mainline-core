# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/edit_task'

describe EditTask do
  cover 'EditTask*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @browse = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    @shop = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Shop', position: 2000)
    @task = Task.create(activity_id: @browse.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
  end

  def edit(name: 'Search', activity_id: @browse.id)
    EditTask.call(task: @task, actor: @person.actor, name: name, activity_id: activity_id)
  end

  it 'renames the task in place' do
    result = edit(name: 'Find')

    assert_predicate result, :success?
    assert_empty result.errors
    @task.reload

    assert_equal 'Find', @task.name
    assert_equal 1000, @task.position
  end

  it 'records an edited event with before and after' do
    edit(name: 'Find', activity_id: @shop.id)

    event = Event.where(entity_id: @task.id, action: 'edited').first

    assert_equal @person.actor_id, event.actor_id
    assert_equal({ 'name' => 'Search', 'activity_id' => @browse.id }, event.before_state)
    assert_equal({ 'name' => 'Find', 'activity_id' => @shop.id }, event.after_state)
  end

  it 'moves the task to the end of another activity' do
    Task.create(activity_id: @shop.id, map_id: @map.id, team_id: @team.id, name: 'Pay', position: 3000)

    edit(activity_id: @shop.id)
    @task.reload

    assert_equal @shop.id, @task.activity_id
    assert_equal 4000, @task.position
  end

  it 'moves the task into an empty activity' do
    edit(activity_id: @shop.id)
    @task.reload

    assert_equal 1000, @task.position
  end

  it 'requires a name' do
    result = edit(name: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal 'Search', @task.reload.name
  end

  it 'rejects a name over 100 characters' do
    assert_predicate edit(name: 'x' * 100), :success?

    result = edit(name: 'x' * 101)

    assert_equal 1, result.errors.size
  end

  it 'requires an activity' do
    result = edit(activity_id: nil)

    assert_equal 1, result.errors.size
  end

  it 'rejects an activity that does not exist' do
    result = edit(activity_id: SecureRandom.uuid)

    assert_equal 1, result.errors.size
    assert_equal @browse.id, @task.reload.activity_id
  end

  it 'rejects an activity on another map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)
    other = Activity.create(map_id: other_map.id, team_id: @team.id, name: 'Elsewhere', position: 1000)

    result = edit(activity_id: other.id)

    assert_equal 1, result.errors.size
    assert_equal @browse.id, @task.reload.activity_id
  end

  it 'rejects an archived activity' do
    @shop.update(archived_at: Time.now)

    result = edit(activity_id: @shop.id)

    assert_equal 1, result.errors.size
  end

  it 'reports every error at once' do
    result = edit(name: nil, activity_id: nil)

    assert_equal 2, result.errors.size
  end
end
