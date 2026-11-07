# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_persona'

describe CreatePersona do
  cover 'CreatePersona*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
  end

  def create(name: 'Visitor', description: 'Browses')
    CreatePersona.call(map: @map, team: @team, actor: @person.actor, name: name, description: description)
  end

  it 'creates a persona on the map' do
    result = create

    assert_predicate result, :success?
    assert_empty result.errors
    assert_equal 'Visitor', result.persona.name
    assert_equal 'Browses', result.persona.description
    assert_equal @map.id, result.persona.map_id
    assert_equal @team.id, result.persona.team_id
  end

  it 'places the persona after the last one on the map' do
    first = create(name: 'First').persona
    second = create(name: 'Second').persona

    assert_equal 1000, first.position
    assert_equal 2000, second.position
  end

  it 'records a created event' do
    persona = create.persona

    event = Event.where(entity_id: persona.id, action: 'created').first

    assert_equal @person.actor_id, event.actor_id
    assert_equal({ 'name' => 'Visitor', 'position' => 1000 }, event.after_state)
  end

  it 'requires a name' do
    result = create(name: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal 0, Persona.where(map_id: @map.id).count
  end

  it 'rejects a name over 100 characters' do
    assert_predicate create(name: 'x' * 100), :success?

    result = create(name: 'x' * 101)

    assert_equal 1, result.errors.size
  end
end
