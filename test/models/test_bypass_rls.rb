# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/bypass_rls'

describe BypassRLS do
  cover 'BypassRLS*'

  before do
    @team = Team.create(name: 'RLS Test')
    SetTeamContext.call(@team.id)
    @map = Map.create(team_id: @team.id, name: 'Test Map', position: 1000)
  end

  it 'allows cross-team reads inside the block' do
    other_team = Team.create(name: 'Other')
    DB.run("SELECT set_config('app.rls_bypass', 'false', false)")
    DB.run("SELECT set_config('app.current_team_id', '#{other_team.id}', false)")

    result = BypassRLS.call { Map.where(team_id: @team.id).all }

    refute_empty result
  end

  it 'isolates invitations by team' do
    inviter = Person.create(name: 'Buyer', email: 'rls-buyer@test.mainline')
    Invitation.create(
      team_id: @team.id, email: 'dev@corp.co',
      token: SecureRandom.urlsafe_base64(32),
      invited_by: inviter.id,
      expires_at: Time.now + 86_400
    )

    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)

    assert_empty Invitation.all
  end

  it 'isolates scenarios by team' do
    persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
    task = Task.create(
      activity_id: activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Search', position: 1000
    )
    person = Person.create(name: 'Alice', email: 'rls-alice@test.mainline')
    story = Story.create(
      task_id: task.id, map_id: @map.id, team_id: @team.id,
      title: 'Story', position: 1000, created_by_id: person.id
    )
    Scenario.create(
      story_id: story.id, given_text: 'a user', when_text: 'they search',
      then_text: 'results appear', position: 1000
    )

    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)

    assert_empty Scenario.all
  end

  it 'isolates map view prefs by team' do
    person = Person.create(name: 'Prefs', email: 'rls-prefs@test.mainline')
    DB[:map_view_prefs].insert(person_id: person.id, map_id: @map.id, active: true)

    other_team = Team.create(name: 'Other')
    SetTeamContext.call(other_team.id)

    assert_empty DB[:map_view_prefs].all
  end

  it 'restores bypass to false after the block' do
    BypassRLS.call { nil }

    val = DB["SELECT current_setting('app.rls_bypass', true)"].get

    assert_equal 'false', val
  end

  it 'restores bypass to false even when block raises' do
    begin
      BypassRLS.call { raise 'boom' }
    rescue RuntimeError
      nil
    end

    val = DB["SELECT current_setting('app.rls_bypass', true)"].get

    assert_equal 'false', val
  end
end
