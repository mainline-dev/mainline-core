# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/create_activity'

describe CreateActivity do
  cover 'CreateActivity*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @visitor = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Visitor', position: 1000)
    @admin = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Admin', position: 2000)
  end

  def create(name: 'Browse', persona_ids: [@visitor.id])
    CreateActivity.call(map: @map, team: @team, actor: @person.actor, name: name, persona_ids: persona_ids)
  end

  it 'creates an activity on the map' do
    result = create

    assert_predicate result, :success?
    assert_empty result.errors
    assert_equal 'Browse', result.activity.name
    assert_equal @map.id, result.activity.map_id
    assert_equal @team.id, result.activity.team_id
  end

  it 'places the activity after the last one on the map' do
    first = create(name: 'First').activity
    second = create(name: 'Second').activity

    assert_equal 1000, first.position
    assert_equal 2000, second.position
  end

  it 'links the activity to each persona' do
    activity = create(persona_ids: [@visitor.id, @admin.id]).activity

    links = ActivityPersona.where(activity_id: activity.id)

    assert_equal [@admin.id, @visitor.id].sort, links.select_map(:persona_id).sort
    assert_equal [@team.id], links.select_map(:team_id).uniq
  end

  it 'records persona_added and created events under one correlation' do
    activity = create(persona_ids: [@visitor.id, @admin.id]).activity

    events = Event.where(entity_id: activity.id).order(:event_no).all

    assert_equal %w[persona_added persona_added created], events.map(&:action)
    added_ids = events.first(2).map { |e| e.after_state['persona_id'] }

    assert_equal [@visitor.id, @admin.id], added_ids
    assert_equal({ 'name' => 'Browse', 'position' => 1000, 'persona_ids' => [@visitor.id, @admin.id] },
      events.last.after_state)
    assert_equal 1, events.map(&:correlation_id).uniq.size
    refute_nil events.first.correlation_id
    assert_equal [@person.actor_id], events.map(&:actor_id).uniq
  end

  it 'requires a name' do
    result = create(name: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal 0, Activity.where(map_id: @map.id).count
  end

  it 'rejects a name over 100 characters' do
    assert_predicate create(name: 'x' * 100), :success?

    result = create(name: 'x' * 101)

    assert_equal 1, result.errors.size
  end

  it 'requires at least one persona' do
    result = create(persona_ids: [])

    assert_equal 1, result.errors.size
  end

  it 'rejects a persona that does not exist' do
    result = create(persona_ids: [@visitor.id, SecureRandom.uuid])

    assert_equal 1, result.errors.size
  end

  it 'rejects a persona on another map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)
    elsewhere = Persona.create(map_id: other_map.id, team_id: @team.id, name: 'Elsewhere', position: 1000)

    result = create(persona_ids: [elsewhere.id])

    assert_equal 1, result.errors.size
  end

  it 'rejects an archived persona' do
    @visitor.update(archived_at: Time.now)

    result = create

    assert_equal 1, result.errors.size
  end

  it 'reports every error at once' do
    result = create(name: nil, persona_ids: [])

    assert_equal 2, result.errors.size
  end
end
