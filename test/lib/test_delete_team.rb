# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/delete_team'

describe DeleteTeam do
  cover 'DeleteTeam*'

  before do
    @team = Team.create(name: 'Doomed')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@doomed.co')
    @membership = TeamMembership.create(team_id: @team.id, person_id: @person.id)
  end

  it 'deletes the team' do
    DeleteTeam.call(team: @team)

    assert_nil Team[@team.id]
  end

  it 'deletes memberships' do
    DeleteTeam.call(team: @team)

    assert_equal 0, TeamMembership.where(team_id: @team.id).count
  end

  it 'deletes invitations' do
    DB[:invitations].insert(
      id: Sequel.lit('gen_random_uuid()'), team_id: @team.id,
      token: SecureRandom.uuid, invited_by: @person.id,
      expires_at: Time.now + 86_400, created_at: Time.now,
      email_ciphertext: 'x', email_bidx: 'y'
    )
    DeleteTeam.call(team: @team)

    assert_equal 0, Invitation.where(team_id: @team.id).count
  end

  it 'deletes team data via SQL function' do
    map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    persona = Persona.create(map_id: map.id, team_id: @team.id, name: 'Dev', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Build', position: 1000)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Code', position: 1000)
    Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Do it', position: 1000, created_by_id: @person.id)

    DeleteTeam.call(team: @team)

    assert_equal 0, Map.where(team_id: @team.id).count
    assert_equal 0, Activity.where(team_id: @team.id).count
    assert_equal 0, Task.where(team_id: @team.id).count
    assert_equal 0, Story.where(team_id: @team.id).count
  end

  it "deletes the team's museum items, promoted or not" do
    map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Build', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Code', position: 1000)
    story = Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Do it', position: 1000, created_by_id: @person.id)
    MuseumItem.create(team_id: @team.id, source_key: 'PROJ-1', issue_type: 'Story', summary: 'Waiting')
    MuseumItem.create(team_id: @team.id, source_key: 'PROJ-2', issue_type: 'Story', summary: 'Promoted',
      story_id: story.id, promoted_at: Time.now)

    DeleteTeam.call(team: @team)

    assert_equal 0, MuseumItem.where(team_id: @team.id).count
  end

  it "deletes the team's museum imports" do
    MuseumImport.create(team_id: @team.id, actor_id: @person.actor_id, file_name: 'jira.csv', status: 'imported')

    DeleteTeam.call(team: @team)

    assert_equal 0, MuseumImport.where(team_id: @team.id).count
  end

  it 'deletes orphaned person and their actor' do
    person_id = @person.id
    actor_id = @person.actor_id

    DeleteTeam.call(team: @team)

    assert_nil Person[person_id]
    assert_nil Actor[actor_id]
  end

  it 'deletes orphaned person with no identity' do
    DeleteTeam.call(team: @team)

    assert_nil Person[@person.id]
    assert_equal 0, PersonIdentity.where(person_id: @person.id).count
  end

  it 'keeps person who signed up with email' do
    email_bidx = BlindIndex.generate_bidx('alice@doomed.co', key: Lockbox.master_key)
    PersonIdentity.create(
      person_id: @person.id, provider: 'email',
      provider_subject: email_bidx, email: 'alice@doomed.co',
      password_digest: 'x'
    )

    DeleteTeam.call(team: @team)

    refute_nil Person[@person.id]
    assert_equal 1, PersonIdentity.where(person_id: @person.id).count
  end

  it 'keeps person who signed up with OAuth' do
    DB[:person_identities].insert(
      id: Sequel.lit('gen_random_uuid()'), person_id: @person.id,
      provider: 'google', provider_subject: '123', created_at: Time.now,
      email_ciphertext: 'x'
    )

    DeleteTeam.call(team: @team)

    refute_nil Person[@person.id]
    assert_equal 1, PersonIdentity.where(person_id: @person.id).count
  end

  it 'deletes only the orphaned person when another person has a different team' do
    bob = Person.create(name: 'Bob', email: 'bob@doomed.co')
    TeamMembership.create(team_id: @team.id, person_id: bob.id)
    other_team = Team.create(name: 'Survivor')
    TeamMembership.create(team_id: other_team.id, person_id: bob.id)

    DeleteTeam.call(team: @team)

    assert_nil Person[@person.id]
    refute_nil Person[bob.id]
  end

  it 'keeps person who has membership on another team' do
    other_team = Team.create(name: 'Survivor')
    TeamMembership.create(team_id: other_team.id, person_id: @person.id)

    DeleteTeam.call(team: @team)

    refute_nil Person[@person.id]
  end

  it 'keeps person who is creator of another team' do
    Team.create(name: 'Owned', creator_id: @person.id)

    DeleteTeam.call(team: @team)

    refute_nil Person[@person.id]
  end

  it 'deletes webhook actor' do
    webhook_actor = Actor.create(name: 'webhook', kind: 'system')
    @team.update(webhook_actor_id: webhook_actor.id)

    DeleteTeam.call(team: @team.refresh)

    assert_nil Actor[webhook_actor.id]
  end

  it 'deletes the MCP actor' do
    mcp_actor = Actor.create(name: 'mcp', kind: 'system')
    @team.update(mcp_actor_id: mcp_actor.id)

    DeleteTeam.call(team: @team.refresh)

    assert_nil Actor[mcp_actor.id]
  end

  it 'does not delete webhook actor when absent' do
    actor_count = Actor.count

    DeleteTeam.call(team: @team)

    assert_equal actor_count - 1, Actor.count
  end
end
