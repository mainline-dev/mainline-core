# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_story'

describe CreateStory do
  cover 'CreateStory*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    @task = Task.create(activity_id: @activity.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
  end

  def create(title: 'Find things', task_id: @task.id)
    CreateStory.call(map: @map, team: @team, actor: @person.actor, person: @person, title: title, task_id: task_id)
  end

  it 'creates a planned story under the task' do
    result = create

    assert_predicate result, :success?
    assert_empty result.errors
    story = result.story

    assert_equal 'Find things', story.title
    assert_equal 'planned', story.status
    assert_equal [@task.id, @map.id, @team.id, @person.id], [story.task_id, story.map_id, story.team_id, story.created_by_id]
  end

  it 'places the story after the last story in the task' do
    first = create(title: 'First').story
    second = create(title: 'Second').story

    assert_operator second.position, :>, first.position
  end

  it 'records a created event by the actor' do
    story = create.story

    event = Event.where(entity_id: story.id, action: 'created').first

    assert_equal @person.actor_id, event.actor_id
    assert_equal 'Find things', event.after_state['title']
  end

  it 'requires a title' do
    result = create(title: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal 0, Story.where(map_id: @map.id).count
  end

  it 'rejects a title over 200 characters' do
    assert_predicate create(title: 'x' * 200), :success?

    refute_predicate create(title: 'x' * 201), :success?
  end

  it 'requires a task on this map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)
    other_activity = Activity.create(map_id: other_map.id, team_id: @team.id, name: 'Elsewhere', position: 1000)
    other_task = Task.create(activity_id: other_activity.id, map_id: other_map.id, team_id: @team.id, name: 'There', position: 1000)

    refute_predicate create(task_id: nil), :success?
    refute_predicate create(task_id: other_task.id), :success?
  end

  it 'refuses an archived task' do
    @task.update(archived_at: Time.now)

    refute_predicate create, :success?
  end

  it 'refuses when the map has reached its story limit' do
    result = ResourceCap.stub(:stories_per_map, :blocked) { create }

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
  end
end
