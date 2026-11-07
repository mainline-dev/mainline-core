# test/models/test_activity_persona.rb
# frozen_string_literal: true

require_relative '../model_spec_helper'

describe 'Activity must have at least one persona' do
  cover 'ActivityPersona*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(
      map_id: @map.id, team_id: @team.id, name: 'Visitor', position: 1000
    )
  end

  def create_activity_with_persona
    activity = nil
    DB.transaction(savepoint: true) do
      activity = Activity.create(
        map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000
      )
      ActivityPersona.create(
        activity_id: activity.id, persona_id: @persona.id, team_id: @team.id
      )
    end
    activity
  end

  it 'cannot remove the last persona from an activity' do
    activity = create_activity_with_persona

    assert_raises(Sequel::DatabaseError) do
      DB.transaction(savepoint: true) do
        ActivityPersona
          .where(activity_id: activity.id, persona_id: @persona.id)
          .delete
        DB.run 'SET CONSTRAINTS ALL IMMEDIATE'
      end
    end
  end

  it 'can remove a persona if another remains' do
    activity = create_activity_with_persona
    second = Persona.create(
      map_id: @map.id, team_id: @team.id, name: 'Admin', position: 2000
    )
    ActivityPersona.create(
      activity_id: activity.id, persona_id: second.id, team_id: @team.id
    )

    ActivityPersona
      .where(activity_id: activity.id, persona_id: @persona.id)
      .delete

    remaining = ActivityPersona.where(activity_id: activity.id).count

    assert_equal 1, remaining
  end

  it 'allows removing last persona when app.allow_team_deletion is set' do
    activity = create_activity_with_persona

    DB.transaction(savepoint: true) do
      DB.run("SELECT set_config('app.allow_team_deletion', 'true', true)")
      ActivityPersona
        .where(activity_id: activity.id, persona_id: @persona.id)
        .delete
      DB.run('SET CONSTRAINTS check_min_one_persona IMMEDIATE')
    end

    assert_equal 0, ActivityPersona.where(activity_id: activity.id).count
  end

  it 'cannot create an activity without any persona' do
    assert_raises(Sequel::DatabaseError) do
      DB.transaction(savepoint: true) do
        Activity.create(
          map_id: @map.id, team_id: @team.id, name: 'Orphan', position: 2000
        )
        DB.run 'SET CONSTRAINTS ALL IMMEDIATE'
      end
    end
  end
end
