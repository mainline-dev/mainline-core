# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Account deletion' do
  include MainlineDSL

  before do
    setup_team
  end

  it 'account holder can delete team with correct confirmation' do
    add_person(name: 'Alice')
    create_map
    visitor = create_persona('Visitor')
    browse = create_activity('Browse', for_personas: [visitor])
    task = create_task('Search', under_activity: browse)
    story = create_story('Find things', under_task: task)
    create_scenario(story, given_text: 'a visitor', when_text: 'they search', then_text: 'results appear')

    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    login_as(holder)

    team_id = @team.id
    holder_id = holder.id

    resp = driver.submit_delete_team(@team, confirmation: "DELETE #{@team.name}")

    assert_equal 302, resp.status
    assert_equal '/', URI.parse(resp['Location']).path

    assert_nil Team[team_id]
    assert_equal 0, Story.where(team_id: team_id).count
    assert_equal 0, Event.where(team_id: team_id).count
    assert_equal 0, Map.where(team_id: team_id).count
    assert_equal 0, TeamMembership.where(team_id: team_id).count
    assert_nil Person[holder_id]
  end

  it 'wrong confirmation is rejected' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    login_as(holder)

    resp = driver.submit_delete_team(@team, confirmation: 'wrong')

    assert_equal 302, resp.status
    assert_includes resp['Location'], '/account/delete'

    refute_nil Team[@team.id]
  end

  it 'non-creator cannot access delete page' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)

    alice = add_person(name: 'Alice')
    login_as(alice)

    resp = driver.visit_delete_team(@team)

    assert_equal 403, resp.status
  end

  it 'person kept if they have other team memberships' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)

    other_team = Team.create(name: 'Other Team')
    TeamMembership.create(team_id: other_team.id, person_id: holder.id, working: false)
    other_team.update(creator_id: holder.id)

    login_as(holder)

    holder_id = holder.id
    resp = driver.submit_delete_team(@team, confirmation: "DELETE #{@team.name}")

    assert_equal 302, resp.status
    assert_nil Team[@team.id]

    refute_nil Person[holder_id]
  end

  it 'person kept when they are creator of another team' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)

    Team.create(name: 'Other Team', creator_id: holder.id)
    login_as(holder)

    holder_id = holder.id
    resp = driver.submit_delete_team(@team, confirmation: "DELETE #{@team.name}")

    assert_equal 302, resp.status
    assert_nil Team[@team.id]
    refute_nil Person[holder_id]
  end

  it 'session is cleared after deletion' do
    holder = Person.create(name: 'Buyer', email: 'buyer@corp.co')
    TeamMembership.create(team_id: @team.id, person_id: holder.id, working: false)
    @team.update(creator_id: holder.id)
    login_as(holder)

    driver.submit_delete_team(@team, confirmation: "DELETE #{@team.name}")

    resp = driver.visit_teams

    assert_equal 302, resp.status
    assert_equal '/login', URI.parse(resp['Location']).path
  end
end
