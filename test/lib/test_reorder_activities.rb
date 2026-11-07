# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/reorder_activities'

describe ReorderActivities do
  cover 'ReorderActivities*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
  end

  def create_activity(name)
    pos = (Activity.where(map_id: @map.id).max(:position) || 0) + 1000
    Activity.create(map_id: @map.id, team_id: @team.id, name: name, position: pos)
  end

  it 'reorders activities to match the given ID order' do
    a = create_activity('A')
    b = create_activity('B')
    c = create_activity('C')

    result = ReorderActivities.call(
      map: @map, activity_ids: [c.id, a.id, b.id], actor: @person.actor
    )

    assert_nil result

    ordered = Activity.where(map_id: @map.id).order(:position).select_map(:name)

    assert_equal %w[C A B], ordered
  end

  it 'returns :not_found for non-existent activity ID' do
    create_activity('A')

    result = ReorderActivities.call(
      map: @map, activity_ids: [SecureRandom.uuid], actor: @person.actor
    )

    assert_equal :not_found, result
  end

  it 'records reorder events with position state' do
    a = create_activity('A')
    b = create_activity('B')

    ReorderActivities.call(
      map: @map, activity_ids: [b.id, a.id], actor: @person.actor
    )

    event = Event.where(entity_id: b.id, action: 'reordered').first

    refute_nil event
    assert_equal 1000, event.after_state['position']
  end

  it 'assigns positions as consecutive multiples of GAP' do
    a = create_activity('A')
    b = create_activity('B')
    c = create_activity('C')

    ReorderActivities.call(
      map: @map, activity_ids: [c.id, a.id, b.id], actor: @person.actor
    )

    positions = Activity.where(map_id: @map.id).order(:position).select_map(:position)

    assert_equal [1000, 2000, 3000], positions
  end

  it 'does not reposition activities in other maps' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)
    bystander = Activity.create(map_id: other_map.id, team_id: @team.id, name: 'Bystander', position: 1000)
    a = create_activity('A')
    original_pos = bystander.position

    ReorderActivities.call(
      map: @map, activity_ids: [a.id], actor: @person.actor
    )

    assert_equal original_pos, bystander.reload.position
  end

  it 'does not reposition archived activities in the same map' do
    a = create_activity('A')
    archived = create_activity('Archived')
    archived.update(archived_at: Time.now)
    original_pos = archived.position

    ReorderActivities.call(
      map: @map, activity_ids: [a.id], actor: @person.actor
    )

    assert_equal original_pos, archived.reload.position
  end

  it 'reorders even when an archived activity holds a target position' do
    persona = Persona.create(
      map_id: @map.id, team_id: @team.id, name: 'Visitor', position: 1000
    )
    archived = create_activity('Archived')
    b = create_activity('B')
    c = create_activity('C')
    [archived, b, c].each do |activity|
      ActivityPersona.create(
        activity_id: activity.id, persona_id: persona.id, team_id: @team.id
      )
    end
    archived.update(archived_at: Time.now)

    DB.run 'SET CONSTRAINTS ALL IMMEDIATE'

    result = ReorderActivities.call(
      map: @map, activity_ids: [c.id, b.id], actor: @person.actor
    )

    assert_nil result

    ordered = Activity.where(map_id: @map.id, archived_at: nil)
      .order(:position).select_map(:name)

    assert_equal %w[C B], ordered
  end

  it 'ignores archived activities in lookup' do
    archived = create_activity('Archived')
    archived.update(archived_at: Time.now)

    result = ReorderActivities.call(
      map: @map, activity_ids: [archived.id], actor: @person.actor
    )

    assert_equal :not_found, result
  end

  it 'skips reorder event when position does not change' do
    a = create_activity('Only')

    ReorderActivities.call(
      map: @map, activity_ids: [a.id], actor: @person.actor
    )

    assert_empty Event.where(entity_id: a.id, action: 'reordered').all
  end

  it 'shares a correlation_id across all events' do
    a = create_activity('A')
    b = create_activity('B')
    c = create_activity('C')

    ReorderActivities.call(
      map: @map, activity_ids: [c.id, b.id, a.id], actor: @person.actor
    )

    events = Event.where(entity_id: [a.id, b.id, c.id], action: 'reordered').all

    assert_operator events.size, :>=, 2
    ids = events.map(&:correlation_id).uniq

    assert_equal 1, ids.size
    refute_nil ids.first
  end

  it 'returns nil on success' do
    a = create_activity('A')

    result = ReorderActivities.call(
      map: @map, activity_ids: [a.id], actor: @person.actor
    )

    assert_nil result
  end

  it 'uses refreshed entity in events' do
    a = create_activity('A')
    b = create_activity('B')

    ReorderActivities.call(
      map: @map, activity_ids: [b.id, a.id], actor: @person.actor
    )

    event = Event.where(entity_id: a.id, action: 'reordered').first

    refute_nil event
    assert_equal a.reload.map_id, event.map_id
  end
end
