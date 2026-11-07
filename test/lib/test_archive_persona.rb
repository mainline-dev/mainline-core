# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/archive_persona'

describe ArchivePersona do
  cover 'ArchivePersona*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Visitor', position: 1000)
    @other = Persona.create(map_id: @map.id, team_id: @team.id, name: 'Admin', position: 2000)
    @browse = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    @shop = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Shop', position: 2000)
  end

  def link(activity, persona)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
  end

  def archive
    ArchivePersona.call(persona: @persona, actor: @person.actor)
  end

  it 'archives the persona' do
    result = archive

    assert_predicate result, :success?
    assert_empty result.errors
    refute_nil @persona.reload.archived_at
  end

  it 'records an archived event' do
    archive

    event = Event.where(entity_id: @persona.id, action: 'archived').first

    assert_equal @person.actor_id, event.actor_id
    assert_equal({ 'name' => 'Visitor' }, event.after_state)
  end

  it 'removes links to active activities and keeps links to archived ones' do
    link(@browse, @persona)
    link(@browse, @other)
    link(@shop, @persona)
    @shop.update(archived_at: Time.now)

    archive

    assert_equal [@shop.id], ActivityPersona.where(persona_id: @persona.id).select_map(:activity_id)
    assert_equal [@other.id], ActivityPersona.where(activity_id: @browse.id).select_map(:persona_id)
  end

  it 'refuses when it is the only persona on an activity' do
    link(@browse, @persona)
    link(@shop, @persona)

    result = archive

    refute_predicate result, :success?
    assert_equal 2, result.errors.size
    assert_nil @persona.reload.archived_at
    assert_equal 2, ActivityPersona.where(persona_id: @persona.id).count
  end
end
