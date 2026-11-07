# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/reorder_stories'

describe ReorderStories do
  cover 'ReorderStories*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
    @story_a = create_story('Story A', position: 1000)
    @story_b = create_story('Story B', position: 2000)
    @story_c = create_story('Story C', position: 3000)
  end

  def create_story(title, position:)
    Story.create(
      task_id: @task.id, map_id: @map.id, team_id: @team.id,
      title: title, position: position, created_by_id: @person.id
    )
  end

  def story_order
    Story.where(task_id: @task.id).order(:position).select_map(:id)
  end

  def events_for(story)
    Event.where(entity_id: story.id, action: 'reordered').all
  end

  it 'moves a story down one position' do
    ReorderStories.call(task: @task, story_ids: [@story_b.id, @story_a.id, @story_c.id], actor: @person.actor)

    assert_equal [@story_b.id, @story_a.id, @story_c.id], story_order
    assert_equal 1, events_for(@story_a).size
    assert_equal 1, events_for(@story_b).size
    assert_equal 0, events_for(@story_c).size
  end

  it 'moves a story up one position' do
    ReorderStories.call(task: @task, story_ids: [@story_b.id, @story_a.id, @story_c.id], actor: @person.actor)

    assert_equal [@story_b.id, @story_a.id, @story_c.id], story_order
  end

  it 'moves a story to the end' do
    ReorderStories.call(task: @task, story_ids: [@story_b.id, @story_c.id, @story_a.id], actor: @person.actor)

    assert_equal [@story_b.id, @story_c.id, @story_a.id], story_order
    assert_equal 1, events_for(@story_a).size
    assert_equal 1, events_for(@story_b).size
    assert_equal 1, events_for(@story_c).size
  end

  it 'moves a story to the start' do
    ReorderStories.call(task: @task, story_ids: [@story_c.id, @story_a.id, @story_b.id], actor: @person.actor)

    assert_equal [@story_c.id, @story_a.id, @story_b.id], story_order
    assert_equal 1, events_for(@story_a).size
    assert_equal 1, events_for(@story_b).size
    assert_equal 1, events_for(@story_c).size
  end

  it 'reorders when task has an archived story' do
    @story_b.update(archived_at: Time.now)
    ReorderStories.call(task: @task, story_ids: [@story_c.id, @story_a.id], actor: @person.actor)
    visible = Story.where(task_id: @task.id, archived_at: nil).order(:position).select_map(:id)

    assert_equal [@story_c.id, @story_a.id], visible
  end

  it 'reorders a subset without colliding with non-participating stories' do
    # Simulates slice view: reorder C,A (slice 1) while B sits at position 2000 (slice 2)
    # C→1000, A→2000 would collide with B's 2000
    ReorderStories.call(task: @task, story_ids: [@story_c.id, @story_a.id], actor: @person.actor)
    positions = Story.where(task_id: @task.id, archived_at: nil).order(:position).select_map([:id, :position])
    ids = positions.map(&:first)

    assert_includes ids, @story_c.id
    assert_includes ids, @story_a.id
    assert_includes ids, @story_b.id
    pos = positions.map(&:last)

    assert_equal pos, pos.sort
    assert_equal pos, pos.uniq
    c_pos = positions.find { |id, _| id == @story_c.id }.last
    a_pos = positions.find { |id, _| id == @story_a.id }.last

    assert_operator c_pos, :<, a_pos, 'Story C should be before Story A'
  end

  it 'records no events for a no-op reorder' do
    original = story_order
    ReorderStories.call(task: @task, story_ids: original, actor: @person.actor)

    assert_equal original, story_order
    assert_equal 0, events_for(@story_a).size
    assert_equal 0, events_for(@story_b).size
    assert_equal 0, events_for(@story_c).size
  end

  describe 'cross-task move' do
    before do
      @activity = Activity.where(map_id: @map.id).first
      @task_b = Task.create(activity_id: @activity.id, map_id: @map.id, team_id: @team.id, name: 'Filter', position: 2000)
      @story_x = Story.create(
        task_id: @task_b.id, map_id: @map.id, team_id: @team.id,
        title: 'Story X', position: 1000, created_by_id: @person.id
      )
      @story_y = Story.create(
        task_id: @task_b.id, map_id: @map.id, team_id: @team.id,
        title: 'Story Y', position: 2000, created_by_id: @person.id
      )
    end

    def task_changed_events(story)
      Event.where(entity_id: story.id, action: 'task_changed').all
    end

    it 'moves a story to a different task' do
      ReorderStories.call(task: @task, story_ids: [@story_x.id], actor: @person.actor, map_id: @map.id)

      @story_x.refresh

      assert_equal @task.id, @story_x.task_id
      assert_equal 1, task_changed_events(@story_x).size

      evt = task_changed_events(@story_x).first

      assert_equal @task_b.id, evt.before_state['task_id']
      assert_equal @task.id, evt.after_state['task_id']
    end

    it 'positions the moved story among existing stories in the target task' do
      ids = [@story_x.id, @story_a.id, @story_b.id, @story_c.id]
      ReorderStories.call(task: @task, story_ids: ids, actor: @person.actor, map_id: @map.id)

      order = Story.where(task_id: @task.id, archived_at: nil).order(:position).select_map(:id)

      assert_equal [@story_x.id, @story_a.id, @story_b.id, @story_c.id], order
    end

    it 'blocks released story from changing task' do
      TeamMembership.create(team_id: @team.id, person_id: @person.id)
      bob = Person.create(name: 'Bob', email: 'bob@test.mainline')
      TeamMembership.create(team_id: @team.id, person_id: bob.id)
      @story_x.update(status: 'active')
      StoryAssignment.create(story_id: @story_x.id, person_id: @person.id, team_id: @team.id)
      StoryAssignment.create(story_id: @story_x.id, person_id: bob.id, team_id: @team.id)
      @story_x.update(status: 'released', released_at: Time.now)
      StoryAssignment.where(story_id: @story_x.id).delete

      result = ReorderStories.call(task: @task, story_ids: [@story_x.id], actor: @person.actor, map_id: @map.id)

      @story_x.refresh

      assert_equal @task_b.id, @story_x.task_id
      assert_equal :released_story, result
    end

    it 'cross-task move with slice change in one call' do
      slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)

      ReorderStories.call(
        task: @task, story_ids: [@story_x.id], actor: @person.actor,
        map_id: @map.id, release_slice_id: slice.id
      )

      @story_x.refresh

      assert_equal @task.id, @story_x.task_id
      assert_equal slice.id, @story_x.release_slice_id
      assert_equal 1, task_changed_events(@story_x).size
      assert_equal 1, Event.where(entity_id: @story_x.id, action: 'slice_changed').count
    end

    it 'same-task reorder still works without map_id' do
      ReorderStories.call(task: @task, story_ids: [@story_c.id, @story_a.id, @story_b.id], actor: @person.actor)

      assert_equal [@story_c.id, @story_a.id, @story_b.id], story_order
    end
  end
end
