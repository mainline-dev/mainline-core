# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/reorder_stories'

describe ReorderStories do
  cover 'ReorderStories*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: @activity.id, persona_id: @persona.id, team_id: @team.id)
    @task = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Search', position: 1000
    )
  end

  def create_story(title)
    pos = (Story.where(task_id: @task.id).max(:position) || 0) + 1000
    Story.create(
      task_id: @task.id, map_id: @map.id, team_id: @team.id,
      title: title, position: pos, created_by_id: @person.id
    )
  end

  it 'returns :not_found for non-existent story ID' do
    result = ReorderStories.call(
      task: @task, story_ids: [SecureRandom.uuid], actor: @person.actor
    )

    assert_equal :not_found, result
  end

  it 'returns :released_story when moving released story across tasks' do
    task2 = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Filter', position: 2000
    )
    story = create_story('Done')
    story.update(status: 'released', released_at: Time.now)

    result = ReorderStories.call(
      task: task2, story_ids: [story.id], actor: @person.actor, map_id: @map.id
    )

    assert_equal :released_story, result
  end

  it 'returns :released_story when changing slice of released story' do
    slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
    story = create_story('Done')
    story.update(status: 'released', released_at: Time.now)

    result = ReorderStories.call(
      task: @task, story_ids: [story.id], actor: @person.actor,
      release_slice_id: slice.id
    )

    assert_equal :released_story, result
  end

  it 'returns :invalid_slice for non-existent slice ID' do
    story = create_story('Planned')

    result = ReorderStories.call(
      task: @task, story_ids: [story.id], actor: @person.actor,
      release_slice_id: SecureRandom.uuid
    )

    assert_equal :invalid_slice, result
  end

  it 'reorders stories to match the given ID order' do
    s1 = create_story('First')
    s2 = create_story('Second')
    s3 = create_story('Third')

    result = ReorderStories.call(
      task: @task, story_ids: [s3.id, s1.id, s2.id], actor: @person.actor
    )

    assert_nil result

    order = Story.where(task_id: @task.id).order(:position).select_map(:title)

    assert_equal %w[Third First Second], order
  end

  it 'moves story from another task into the target' do
    task2 = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Filter', position: 2000
    )
    story = Story.create(
      task_id: task2.id, map_id: @map.id, team_id: @team.id,
      title: 'Mover', position: 1000, created_by_id: @person.id
    )

    ReorderStories.call(
      task: @task, story_ids: [story.id], actor: @person.actor, map_id: @map.id
    )

    assert_equal @task.id, story.refresh.task_id
  end

  it 'records task_changed event for cross-task move' do
    task2 = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Filter', position: 2000
    )
    story = Story.create(
      task_id: task2.id, map_id: @map.id, team_id: @team.id,
      title: 'Mover', position: 1000, created_by_id: @person.id
    )

    ReorderStories.call(
      task: @task, story_ids: [story.id], actor: @person.actor, map_id: @map.id
    )

    event = Event.where(entity_id: story.id, action: 'task_changed').first

    refute_nil event
    assert_equal task2.id, event.before_state['task_id']
    assert_equal @task.id, event.after_state['task_id']
  end

  it 'does not reposition stories in other tasks' do
    task2 = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Filter', position: 2000
    )
    bystander = Story.create(
      task_id: task2.id, map_id: @map.id, team_id: @team.id,
      title: 'Bystander', position: 1000, created_by_id: @person.id
    )
    s1 = create_story('First')
    original_pos = bystander.position

    ReorderStories.call(task: @task, story_ids: [s1.id], actor: @person.actor)

    assert_equal original_pos, bystander.reload.position
  end

  it 'does not reposition archived stories in the same task' do
    s1 = create_story('Active')
    archived = create_story('Archived')
    archived.update(archived_at: Time.now)
    original_pos = archived.position

    ReorderStories.call(task: @task, story_ids: [s1.id], actor: @person.actor)

    assert_equal original_pos, archived.reload.position
  end

  it 'assigns positions as consecutive multiples of GAP' do
    s1 = create_story('A')
    s2 = create_story('B')
    s3 = create_story('C')

    ReorderStories.call(
      task: @task, story_ids: [s3.id, s1.id, s2.id], actor: @person.actor
    )

    positions = Story.where(task_id: @task.id).order(:position).select_map(:position)

    assert_equal [1000, 2000, 3000], positions
  end

  it 'orders non-reordered stories by position not insertion order' do
    s1 = create_story('A')
    create_story('B')
    s3 = create_story('C')
    s4 = create_story('D')
    DB[:stories].where(id: s4.id).update(position: 100)
    DB[:stories].where(id: s3.id).update(position: 200)

    ReorderStories.call(task: @task, story_ids: [s1.id], actor: @person.actor)

    ordered = Story.where(task_id: @task.id).order(:position).select_map(:title)

    assert_equal %w[A D C B], ordered
  end

  it 'skips reorder event when position does not change' do
    s1 = create_story('Only')

    ReorderStories.call(task: @task, story_ids: [s1.id], actor: @person.actor)

    assert_empty Event.where(entity_id: s1.id, action: 'reordered').all
  end

  it 'shares a correlation_id across all events' do
    task2 = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Filter', position: 2000
    )
    s1 = create_story('Local')
    mover = Story.create(
      task_id: task2.id, map_id: @map.id, team_id: @team.id,
      title: 'Mover', position: 1000, created_by_id: @person.id
    )

    ReorderStories.call(
      task: @task, story_ids: [mover.id, s1.id], actor: @person.actor, map_id: @map.id
    )

    events = Event.where(entity_id: [s1.id, mover.id])
      .where(action: %w[task_changed reordered]).all

    assert_operator events.size, :>=, 2
    ids = events.map(&:correlation_id).uniq

    assert_equal 1, ids.size
    refute_nil ids.first
  end

  it 'changes release slice and records event' do
    slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
    story = create_story('Sliceable')

    ReorderStories.call(
      task: @task, story_ids: [story.id], actor: @person.actor,
      release_slice_id: slice.id
    )

    assert_equal slice.id, story.refresh.release_slice_id

    event = Event.where(entity_id: story.id, action: 'slice_changed').first

    refute_nil event
    assert_nil event.before_state['release_slice_id']
    assert_equal slice.id, event.after_state['release_slice_id']
  end

  it 'clears release slice with empty string' do
    slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
    story = create_story('Sliced')
    story.update(release_slice_id: slice.id)

    ReorderStories.call(
      task: @task, story_ids: [story.id], actor: @person.actor,
      release_slice_id: ''
    )

    assert_nil story.refresh.release_slice_id
  end

  it 'skips slice event when slice does not change' do
    slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'MVP', position: 1000)
    story = create_story('Already sliced')
    story.update(release_slice_id: slice.id)

    ReorderStories.call(
      task: @task, story_ids: [story.id], actor: @person.actor,
      release_slice_id: slice.id
    )

    assert_empty Event.where(entity_id: story.id, action: 'slice_changed').all
  end

  it 'ignores archived stories in lookup' do
    archived = create_story('Archived')
    archived.update(archived_at: Time.now)

    result = ReorderStories.call(
      task: @task, story_ids: [archived.id], actor: @person.actor
    )

    assert_equal :not_found, result
  end
end
