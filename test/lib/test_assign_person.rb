# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/assign_person'
require_relative '../../lib/record_event'

describe AssignPerson do
  cover 'AssignPerson*'
  before do
    @team = Team.create(name: 'Test Team')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.co')
    @bob = Person.create(name: 'Bob', email: 'bob@test.co')
    TeamMembership.create(team_id: @team.id, person_id: @person.id, working: true)
    TeamMembership.create(team_id: @team.id, person_id: @bob.id, working: true)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act', position: 1000)
    @task = Task.create(map_id: @map.id, team_id: @team.id, activity_id: @activity.id, name: 'Task', position: 1000)
    @story = Story.create(map_id: @map.id, team_id: @team.id, task_id: @task.id,
      title: 'Test', position: 1000, created_by_id: @person.id)
  end

  it 'assigns a person and returns success' do
    result = AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    assert_predicate result, :success?
    assert_predicate StoryAssignment.where(story_id: @story.id, person_id: @person.id), :any?
  end

  it 'returns error for released story' do
    @story.update(status: 'released', released_at: Time.now)

    result = AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end

  it 'returns error for non-member' do
    outsider = Person.create(name: 'Outsider', email: 'out@test.co')

    result = AssignPerson.call(story: @story, person_id: outsider.id, team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end

  it 'returns error for duplicate assignment' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    result = AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end

  it 'returns error when person is on another active story' do
    other = Story.create(map_id: @map.id, team_id: @team.id, task_id: @task.id,
      title: 'Other', position: 2000, created_by_id: @person.id)
    StoryAssignment.create(story_id: other.id, person_id: @person.id, team_id: @team.id)

    result = AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end

  describe 'with a raised WIP limit' do
    before do
      TeamConstraint.create(
        team_id: @team.id, constraint_key: 'max_active_stories', value: 2,
        min_value: 1, max_value: 5, default_value: 1
      )
      @other = another_story('Other', 2000)
      StoryAssignment.create(story_id: @other.id, person_id: @person.id, team_id: @team.id)
    end

    def another_story(title, position)
      Story.create(map_id: @map.id, team_id: @team.id, task_id: @task.id,
        title: title, position: position, created_by_id: @person.id)
    end

    def assign(story)
      AssignPerson.call(story: story, person_id: @person.id, team: @team, actor_id: @person.actor_id)
    end

    it 'lets a person take stories up to the limit' do
      assert_predicate assign(@story), :success?
    end

    it 'refuses the story past the limit' do
      assign(@story)

      result = assign(another_story('Third', 3000))

      refute_predicate result, :success?
      refute_empty result.errors
    end

    it 'leaves stories in flight when the limit is lowered, and refuses new ones' do
      assign(@story)
      TeamConstraint.where(team_id: @team.id, constraint_key: 'max_active_stories').update(value: 1)

      result = assign(another_story('Third', 3000))

      refute_predicate result, :success?
      assert_equal 2, StoryAssignment.where(person_id: @person.id, team_id: @team.id).count
    end
  end

  it 'activates planned story when second person assigned' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    AssignPerson.call(story: @story, person_id: @bob.id, team: @team, actor_id: @bob.actor_id)

    @story.reload

    assert_equal 'active', @story.status
  end

  it 'activates on first assignment when solo allowed' do
    TeamConstraint.create(team_id: @team.id, constraint_key: 'allow_solo_activation',
      value: 1, min_value: 0, max_value: 1, default_value: 0)

    AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    @story.reload

    assert_equal 'active', @story.status
  end

  it 'does not activate on first assignment when solo not allowed' do
    AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    @story.reload

    assert_equal 'planned', @story.status
  end

  it 'returns friendly error on concurrent duplicate assignment' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)
    other = Story.create(map_id: @map.id, team_id: @team.id, task_id: @task.id,
      title: 'Other', position: 2000, created_by_id: @person.id)

    result = AssignPerson.call(story: other, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end

  it 'returns error when person_id is nil' do
    result = AssignPerson.call(story: @story, person_id: nil, team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end

  it 'returns error when person_id is empty string' do
    result = AssignPerson.call(story: @story, person_id: '', team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end

  it 'returns empty errors on success' do
    result = AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    assert_empty result.errors
  end

  it 'records person_assigned event' do
    AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    event = Event.where(entity_id: @story.id, action: 'person_assigned').first

    refute_nil event
    assert_equal @person.id, event.after_state['person_id']
  end

  it 'records activated event with paired reason when two assigned' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    AssignPerson.call(story: @story, person_id: @bob.id, team: @team, actor_id: @bob.actor_id)

    event = Event.where(entity_id: @story.id, action: 'activated').first

    refute_nil event
    assert_equal 'paired', event.after_state['reason']
    assert_equal 2, event.after_state['assignment_count']
  end

  it 'records activated event with solo reason when solo allowed' do
    TeamConstraint.create(team_id: @team.id, constraint_key: 'allow_solo_activation',
      value: 1, min_value: 0, max_value: 1, default_value: 0)

    AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    event = Event.where(entity_id: @story.id, action: 'activated').first

    refute_nil event
    assert_equal 'solo', event.after_state['reason']
    assert_equal 1, event.after_state['assignment_count']
  end

  it 'activates solo on 1-member team without constraint' do
    TeamMembership.where(person_id: @bob.id).delete

    AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    @story.reload

    assert_equal 'active', @story.status

    event = Event.where(entity_id: @story.id, action: 'activated').first

    assert_equal 'solo', event.after_state['reason']
  end

  it 'records collaboration_changed from solo to paired on activation' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    AssignPerson.call(story: @story, person_id: @bob.id, team: @team, actor_id: @bob.actor_id)

    event = Event.where(entity_id: @story.id, action: 'collaboration_changed').first

    refute_nil event
    assert_equal 'solo', event.before_state['mode']
    assert_equal 'paired', event.after_state['mode']
    assert_equal 2, event.after_state['assignment_count']
  end

  it 'records collaboration_changed when assigning to active story' do
    @story.update(status: 'active')
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    AssignPerson.call(story: @story, person_id: @bob.id, team: @team, actor_id: @bob.actor_id)

    event = Event.where(entity_id: @story.id, action: 'collaboration_changed').first

    refute_nil event
    assert_equal 'solo', event.before_state['mode']
    assert_equal 'paired', event.after_state['mode']
  end

  it 'records ensemble mode when third person assigned' do
    @story.update(status: 'active')
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)
    StoryAssignment.create(story_id: @story.id, person_id: @bob.id, team_id: @team.id)
    charlie = Person.create(name: 'Charlie', email: 'charlie@test.co')
    TeamMembership.create(team_id: @team.id, person_id: charlie.id, working: true)

    AssignPerson.call(story: @story, person_id: charlie.id, team: @team, actor_id: charlie.actor_id)

    event = Event.where(entity_id: @story.id, action: 'collaboration_changed').first

    refute_nil event
    assert_equal 'paired', event.before_state['mode']
    assert_equal 'ensemble', event.after_state['mode']
    assert_equal 3, event.after_state['assignment_count']
  end

  it 'includes person_ids in collaboration_changed event' do
    StoryAssignment.create(story_id: @story.id, person_id: @person.id, team_id: @team.id)

    AssignPerson.call(story: @story, person_id: @bob.id, team: @team, actor_id: @bob.actor_id)

    event = Event.where(entity_id: @story.id, action: 'collaboration_changed').first

    assert_includes event.after_state['person_ids'], @person.id
    assert_includes event.after_state['person_ids'], @bob.id
  end

  it 'records collaboration_changed when assigning first person to active story' do
    @story.update(status: 'active')

    AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    event = Event.where(entity_id: @story.id, action: 'collaboration_changed').first

    refute_nil event
    assert_equal 'planned', event.before_state['mode']
    assert_equal 'solo', event.after_state['mode']
  end

  it 'does not create assignment on validation failure' do
    @story.update(status: 'released', released_at: Time.now)

    AssignPerson.call(story: @story, person_id: @person.id, team: @team, actor_id: @person.actor_id)

    assert_empty StoryAssignment.where(story_id: @story.id).all
  end

  it 'rejects non-working member' do
    TeamMembership.where(team_id: @team.id, person_id: @bob.id).update(working: false)

    result = AssignPerson.call(story: @story, person_id: @bob.id, team: @team, actor_id: @person.actor_id)

    refute_predicate result, :success?
    refute_empty result.errors
  end
end
