# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/edit_activity'

describe EditActivity do
  cover 'EditActivity*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @visitor = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Visitor', position: 1000)
    @admin = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Admin', position: 2000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: @activity.id, persona_id: @visitor.id, team_id: @team.id)
  end

  def edit(name: 'Browse', persona_ids: [@visitor.id])
    EditActivity.call(activity: @activity, actor: @person.actor, name: name, persona_ids: persona_ids)
  end

  def linked_persona_ids
    ActivityPersona.where(activity_id: @activity.id).select_map(:persona_id).sort
  end

  it 'renames the activity' do
    result = edit(name: 'Shop')

    assert_predicate result, :success?
    assert_empty result.errors
    assert_equal 'Shop', @activity.reload.name
  end

  it 'replaces the persona links' do
    edit(persona_ids: [@admin.id])

    assert_equal [@admin.id], linked_persona_ids
    assert_equal [@team.id], ActivityPersona.where(activity_id: @activity.id).select_map(:team_id)
  end

  it 'keeps the link to an archived persona' do
    @visitor.update(archived_at: Time.now)

    edit(persona_ids: [@admin.id])

    assert_equal [@admin.id, @visitor.id].sort, linked_persona_ids
  end

  it 'records an edited event with before and after' do
    edit(name: 'Shop', persona_ids: [@admin.id])

    event = Event.where(entity_id: @activity.id, action: 'edited').first

    assert_equal @person.actor_id, event.actor_id
    assert_equal({ 'name' => 'Browse', 'persona_ids' => [@visitor.id] }, event.before_state)
    assert_equal({ 'name' => 'Shop', 'persona_ids' => [@admin.id] }, event.after_state)
  end

  it 'requires a name' do
    result = edit(name: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal 'Browse', @activity.reload.name
  end

  it 'rejects a name over 100 characters' do
    assert_predicate edit(name: 'x' * 100), :success?

    result = edit(name: 'x' * 101)

    assert_equal 1, result.errors.size
  end

  it 'requires at least one persona' do
    result = edit(persona_ids: [])

    assert_equal 1, result.errors.size
    assert_equal [@visitor.id], linked_persona_ids
  end

  it 'rejects a persona on another map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 2000)
    elsewhere = Persona.create(map_id: other_map.id, team_id: @team.id, name: 'Elsewhere', position: 1000)

    result = edit(persona_ids: [elsewhere.id])

    assert_equal 1, result.errors.size
  end

  it 'rejects an archived persona' do
    @admin.update(archived_at: Time.now)

    result = edit(persona_ids: [@admin.id])

    assert_equal 1, result.errors.size
  end

  it 'reports every error at once' do
    result = edit(name: nil, persona_ids: [])

    assert_equal 2, result.errors.size
  end
end
