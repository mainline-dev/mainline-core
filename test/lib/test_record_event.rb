# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'

describe RecordEvent do
  cover 'RecordEvent*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
  end

  it 'creates an event with required fields' do
    RecordEvent.call(
      actor_id: @person.actor.id, entity: @persona,
      action: 'created',
      after_state: { name: 'User' }
    )

    event = Event.where(entity_id: @persona.id, action: 'created').first

    refute_nil event
    assert_equal @team.id, event.team_id
    assert_equal @map.id, event.map_id
    assert_equal @person.actor.id, event.actor_id
    assert_equal 'persona', event.entity_type
    assert_equal 'User', event.after_state['name']
  end

  it 'stores before_state and after_state' do
    RecordEvent.call(
      actor_id: @person.actor.id, entity: @persona,
      action: 'updated',
      before_state: { name: 'Old' },
      after_state: { name: 'New' }
    )

    event = Event.where(entity_id: @persona.id, action: 'updated').first

    assert_equal 'Old', event.before_state['name']
    assert_equal 'New', event.after_state['name']
  end

  it 'sets correlation_id when provided' do
    cid = SecureRandom.uuid
    RecordEvent.call(
      actor_id: @person.actor.id, entity: @persona,
      action: 'created',
      after_state: { name: 'User' },
      correlation_id: cid
    )

    event = Event.where(entity_id: @persona.id, action: 'created').first

    assert_equal cid, event.correlation_id
  end

  it 'derives entity_type from table name' do
    RecordEvent.call(
      actor_id: @person.actor.id, entity: @persona,
      action: 'created',
      after_state: { name: 'User' }
    )

    event = Event.where(entity_id: @persona.id, action: 'created').first

    assert_equal 'persona', event.entity_type
  end

  it 'entity_type_for derives from table name' do
    assert_equal 'persona', RecordEvent.entity_type_for(Persona)
    assert_equal 'map', RecordEvent.entity_type_for(Map)
  end

  it 'uses explicit map_id when provided' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)

    RecordEvent.call(
      actor_id: @person.actor.id, entity: @persona,
      action: 'created',
      after_state: {},
      map_id: other_map.id
    )

    event = Event.where(entity_id: @persona.id, action: 'created').first

    assert_equal other_map.id, event.map_id
  end
end
