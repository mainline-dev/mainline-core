# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/first_run'
require_relative '../../lib/create_personal_token'
require_relative '../../lib/revoke_grant'

describe FirstRun do
  cover 'FirstRun*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    # Far from the real date, so the steps go by the time they are given.
    @now = Time.utc(2030, 6, 1, 12)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
  end

  # A personal token for the team, made by someone on it. Its grant's ID.
  def give_a_coding_agent(team)
    TeamMembership.create(team_id: team.id, person_id: @person.id, working: true)
    CreatePersonalToken.call(person: @person, name: 'laptop', team_ids: [team.id], expires_on: Date.today + 30)
    OauthGrant.where(person_id: @person.id).get(:id)
  end

  # A map starts the map, so only the tests that need one make it.
  def map
    @map ||= Map.create(team_id: @team.id, name: 'Shop', position: 1000)
  end

  def task
    @task ||= Task.create(activity_id: Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000).id,
      map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
  end

  def story(status: 'planned', **attrs)
    Story.create(task_id: task.id, map_id: map.id, team_id: @team.id, title: 'Pay by card',
      position: (Story.max(:position) || 0) + 1000, created_by_id: @person.id, status: status, **attrs)
  end

  def exhibit(days_ago: 1, source: 'jira', **state)
    MuseumItem.create(team_id: @team.id, source_key: "SHOP-#{MuseumItem.count + 1}", issue_type: 'Story',
      summary: 'Pay by card', source: source, created_at: @now - (days_ago * 86_400), **state)
  end

  def done
    FirstRun.for(@team, now: @now).select { |_, ticked| ticked }.keys
  end

  it 'has every step undone for a new team, in order' do
    assert_equal %i[map promote slice start agent figure], FirstRun.for(@team, now: @now).keys
    assert_empty done
  end

  it 'ticks starting the map once the team has a map' do
    map

    assert_equal [:map], done
  end

  it 'ticks starting the map once a ticket is in the museum' do
    exhibit

    assert_equal [:map], done
  end

  it 'ticks starting the map once stories proposed from a specification are in the museum' do
    exhibit(source: 'mainline')

    assert_equal [:map], done
  end

  it 'ticks pulling what is real once a ticket is promoted' do
    exhibit(promoted_at: @now, story_id: story.id)

    assert_equal %i[map promote], done
  end

  it 'ticks shaping the map once there is a release slice' do
    ReleaseSlice.create(map_id: map.id, team_id: @team.id, name: 'First release', position: 1000)

    assert_equal %i[map slice], done
  end

  it 'ticks one story each once a story has started' do
    story(status: 'active')

    assert_equal %i[map start], done
  end

  it 'leaves one story each undone while every story is planned' do
    story

    assert_equal [:map], done
  end

  it 'ticks the coding agent once someone gives a coding agent the team' do
    give_a_coding_agent(@team)

    assert_equal [:agent], done
  end

  it 'keeps the coding agent ticked once that token is revoked' do
    RevokeGrant.call(person: @person, grant_id: give_a_coding_agent(@team))

    assert_equal [:agent], done
  end

  it 'leaves the coding agent unticked for a token that gives only another team' do
    give_a_coding_agent(Team.create(name: 'Other'))

    assert_empty done
  end

  it 'ticks checking back once the museum can say how much was never pulled' do
    exhibit(days_ago: 90)

    assert_equal %i[map figure], done
  end

  it 'has no first steps once a story has been released' do
    story(status: 'released', released_at: @now)

    assert_nil FirstRun.for(@team, now: @now)
  end
end
