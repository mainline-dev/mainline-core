# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/edit_persona'

describe EditPersona do
  cover 'EditPersona*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Visitor', description: 'Old', position: 1000)
    @other = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Admin', position: 2000)
    @browse = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    @shop = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Shop', position: 2000)
    link(@browse, @persona)
    link(@browse, @other)
  end

  def link(activity, persona)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
  end

  def edit(name: 'Visitor', description: 'Old', activity_ids: [@browse.id])
    EditPersona.call(persona: @persona, actor: @person.actor, name: name, description: description,
      activity_ids: activity_ids)
  end

  def linked_activity_ids
    ActivityPersona.where(persona_id: @persona.id).select_map(:activity_id).sort
  end

  it 'updates the name and description' do
    result = edit(name: 'Shopper', description: 'New')

    assert_predicate result, :success?
    assert_empty result.errors
    @persona.reload

    assert_equal 'Shopper', @persona.name
    assert_equal 'New', @persona.description
  end

  it 'replaces the activity links' do
    edit(activity_ids: [@browse.id, @shop.id])

    assert_equal [@browse.id, @shop.id].sort, linked_activity_ids
    assert_equal [@team.id], ActivityPersona.where(persona_id: @persona.id).select_map(:team_id).uniq
  end

  it 'keeps the link to an archived activity' do
    @browse.update(archived_at: Time.now)

    edit(activity_ids: [@shop.id])

    assert_equal [@browse.id, @shop.id].sort, linked_activity_ids
  end

  it 'records an edited event with before and after' do
    edit(name: 'Shopper', description: 'New', activity_ids: [@shop.id])

    event = Event.where(entity_id: @persona.id, action: 'edited').first

    assert_equal @person.actor_id, event.actor_id
    assert_equal({ 'name' => 'Visitor', 'description' => 'Old', 'activity_ids' => [@browse.id] }, event.before_state)
    assert_equal({ 'name' => 'Shopper', 'description' => 'New', 'activity_ids' => [@shop.id] }, event.after_state)
  end

  it 'requires a name' do
    result = edit(name: nil)

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal 'Visitor', @persona.reload.name
  end

  it 'rejects a name over 100 characters' do
    assert_predicate edit(name: 'x' * 100), :success?

    result = edit(name: 'x' * 101)

    assert_equal 1, result.errors.size
  end

  it 'refuses to leave an activity with no persona' do
    link(@shop, @persona)

    result = edit(activity_ids: [@browse.id])

    refute_predicate result, :success?
    assert_equal 1, result.errors.size
    assert_equal [@browse.id, @shop.id].sort, linked_activity_ids
  end

  it 'allows unlinking an activity another persona still covers' do
    assert_predicate edit(activity_ids: []), :success?
    assert_empty linked_activity_ids
  end

  it 'allows unlinking an archived activity' do
    link(@shop, @persona)
    @shop.update(archived_at: Time.now)

    assert_predicate edit(activity_ids: [@browse.id]), :success?
  end

  it 'reports name errors before orphaned activities' do
    link(@shop, @persona)

    result = edit(name: nil, activity_ids: [])

    assert_equal 1, result.errors.size
  end
end
