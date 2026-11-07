# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/reorder_tasks'

describe ReorderTasks do
  cover 'ReorderTasks*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act A', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Dev', position: 1000)
    ActivityPersona.create(activity_id: @activity.id, persona_id: @persona.id, team_id: @team.id)
  end

  def create_task(name, activity: @activity)
    pos = (Task.where(activity_id: activity.id).max(:position) || 0) + 1000
    Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: name, position: pos)
  end

  it 'reorders tasks to match the given ID order' do
    a = create_task('A')
    b = create_task('B')
    c = create_task('C')

    result = ReorderTasks.call(
      activity: @activity, task_ids: [c.id, a.id, b.id],
      actor: @person.actor, map_id: @map.id
    )

    assert_nil result

    ordered = Task.where(activity_id: @activity.id).order(:position).select_map(:name)

    assert_equal %w[C A B], ordered
  end

  it 'returns :not_found for non-existent task ID' do
    create_task('A')

    result = ReorderTasks.call(
      activity: @activity, task_ids: [SecureRandom.uuid],
      actor: @person.actor, map_id: @map.id
    )

    assert_equal :not_found, result
  end

  it 'returns :not_found when task belongs to a different map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)
    other_act = Activity.create(map_id: other_map.id, team_id: @team.id, name: 'Act B', position: 1000)
    ActivityPersona.create(activity_id: other_act.id, persona_id: @persona.id, team_id: @team.id)
    foreign = Task.create(activity_id: other_act.id, map_id: other_map.id, team_id: @team.id, name: 'Foreign', position: 1000)

    result = ReorderTasks.call(
      activity: @activity, task_ids: [foreign.id],
      actor: @person.actor, map_id: @map.id
    )

    assert_equal :not_found, result
  end

  it 'ignores archived tasks' do
    a = create_task('A')
    archived = create_task('Archived')
    archived.update(archived_at: Time.now)

    result = ReorderTasks.call(
      activity: @activity, task_ids: [a.id, archived.id],
      actor: @person.actor, map_id: @map.id
    )

    assert_equal :not_found, result
  end

  it 'moves task from another activity into the target' do
    other_activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act B', position: 2000)
    ActivityPersona.create(activity_id: other_activity.id, persona_id: @persona.id, team_id: @team.id)
    task = create_task('Mover', activity: other_activity)

    ReorderTasks.call(
      activity: @activity, task_ids: [task.id],
      actor: @person.actor, map_id: @map.id
    )

    assert_equal @activity.id, task.refresh.activity_id
  end

  it 'records task_moved event for cross-activity move' do
    other_activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act B', position: 2000)
    ActivityPersona.create(activity_id: other_activity.id, persona_id: @persona.id, team_id: @team.id)
    task = create_task('Mover', activity: other_activity)

    ReorderTasks.call(
      activity: @activity, task_ids: [task.id],
      actor: @person.actor, map_id: @map.id
    )

    event = Event.where(entity_id: task.id, action: 'task_moved').first

    refute_nil event
    assert_equal other_activity.id, event.before_state['activity_id']
    assert_equal @activity.id, event.after_state['activity_id']
  end

  it 'records reorder events with correct before and after positions' do
    a = create_task('A')
    b = create_task('B')
    old_a_pos = a.position
    old_b_pos = b.position

    ReorderTasks.call(
      activity: @activity, task_ids: [b.id, a.id],
      actor: @person.actor, map_id: @map.id
    )

    event_a = Event.where(entity_id: a.id, action: 'reordered').first
    event_b = Event.where(entity_id: b.id, action: 'reordered').first

    refute_nil event_b
    assert_equal old_b_pos, event_b.before_state['position']
    assert_equal 1000, event_b.after_state['position']

    refute_nil event_a
    assert_equal old_a_pos, event_a.before_state['position']
    assert_equal 2000, event_a.after_state['position']
  end

  it 'skips reorder event when position does not change' do
    a = create_task('A')

    ReorderTasks.call(
      activity: @activity, task_ids: [a.id],
      actor: @person.actor, map_id: @map.id
    )

    reorder_events = Event.where(entity_id: a.id, action: 'reordered').all

    assert_empty reorder_events
  end

  it 'places moved tasks before existing tasks' do
    create_task('Existing')
    other_activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act B', position: 2000)
    ActivityPersona.create(activity_id: other_activity.id, persona_id: @persona.id, team_id: @team.id)
    mover = create_task('Mover', activity: other_activity)

    ReorderTasks.call(
      activity: @activity, task_ids: [mover.id],
      actor: @person.actor, map_id: @map.id
    )

    ordered = Task.where(activity_id: @activity.id).order(:position).select_map(:name)

    assert_equal %w[Mover Existing], ordered
  end

  it 'shares a correlation_id across all events' do
    other_activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act B', position: 2000)
    ActivityPersona.create(activity_id: other_activity.id, persona_id: @persona.id, team_id: @team.id)
    a = create_task('A')
    b = create_task('B', activity: other_activity)

    ReorderTasks.call(
      activity: @activity, task_ids: [b.id, a.id],
      actor: @person.actor, map_id: @map.id
    )

    events = Event.where(entity_id: [a.id, b.id]).where(action: %w[task_moved reordered]).all

    assert_operator events.size, :>=, 2
    correlation_ids = events.map(&:correlation_id).uniq

    assert_equal 1, correlation_ids.size
    refute_nil correlation_ids.first
  end

  it 'preserves relative order of tasks not in the reorder list' do
    a = create_task('A')
    create_task('B')
    c = create_task('C')
    create_task('D')

    ReorderTasks.call(
      activity: @activity, task_ids: [c.id, a.id],
      actor: @person.actor, map_id: @map.id
    )

    ordered = Task.where(activity_id: @activity.id).order(:position).select_map(:name)

    assert_equal %w[C A B D], ordered
  end

  it 'interleaves moved task among existing tasks at the specified position' do
    a = create_task('A')
    b = create_task('B')
    other_activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act B', position: 2000)
    ActivityPersona.create(activity_id: other_activity.id, persona_id: @persona.id, team_id: @team.id)
    mover = create_task('Mover', activity: other_activity)

    ReorderTasks.call(
      activity: @activity, task_ids: [a.id, mover.id, b.id],
      actor: @person.actor, map_id: @map.id
    )

    ordered = Task.where(activity_id: @activity.id).order(:position).select_map(:name)

    assert_equal %w[A Mover B], ordered
  end

  it 'does not reposition tasks in other activities' do
    create_task('A')
    other_activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act B', position: 2000)
    ActivityPersona.create(activity_id: other_activity.id, persona_id: @persona.id, team_id: @team.id)
    bystander = create_task('Bystander', activity: other_activity)
    original_pos = bystander.position

    ReorderTasks.call(activity: @activity, task_ids: [create_task('B').id], actor: @person.actor, map_id: @map.id)

    assert_equal original_pos, bystander.reload.position
  end

  it 'does not reposition archived tasks in the same activity' do
    a = create_task('A')
    b = create_task('B')
    archived = create_task('Archived')
    archived.update(archived_at: Time.now)
    original_pos = archived.position

    ReorderTasks.call(activity: @activity, task_ids: [b.id, a.id], actor: @person.actor, map_id: @map.id)

    assert_equal original_pos, archived.reload.position
  end

  it 'assigns positions as consecutive multiples of GAP' do
    a = create_task('A')
    b = create_task('B')
    c = create_task('C')

    ReorderTasks.call(activity: @activity, task_ids: [c.id, a.id, b.id], actor: @person.actor, map_id: @map.id)

    positions = Task.where(activity_id: @activity.id).order(:position).select_map(:position)

    assert_equal [1000, 2000, 3000], positions
  end

  it 'orders non-reordered tasks by position not insertion order' do
    a = create_task('A')
    create_task('B')
    c = create_task('C')
    d = create_task('D')
    DB[:tasks].where(id: d.id).update(position: 100)
    DB[:tasks].where(id: c.id).update(position: 200)

    ReorderTasks.call(activity: @activity, task_ids: [a.id], actor: @person.actor, map_id: @map.id)

    ordered = Task.where(activity_id: @activity.id).order(:position).select_map(:name)

    assert_equal %w[A D C B], ordered
  end

  it 'records task_moved event with refreshed entity' do
    other_activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Act B', position: 2000)
    ActivityPersona.create(activity_id: other_activity.id, persona_id: @persona.id, team_id: @team.id)
    task = create_task('Mover', activity: other_activity)

    ReorderTasks.call(activity: @activity, task_ids: [task.id], actor: @person.actor, map_id: @map.id)

    event = Event.where(entity_id: task.id, action: 'task_moved').first

    assert_equal @activity.id, event.after_state['activity_id']
    assert_equal @map.id, event.map_id
  end

  it 'returns nil on success' do
    a = create_task('A')

    result = ReorderTasks.call(
      activity: @activity, task_ids: [a.id],
      actor: @person.actor, map_id: @map.id
    )

    assert_nil result
  end
end
