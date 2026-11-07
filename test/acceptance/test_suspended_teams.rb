# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/ci_monitor_dsl'

# A suspended team's pages close. Working members land on their team list;
# the account holder lands on the link the suspension names, or the account
# page when it names none. The CI Monitor stays open. MCP and the deploy
# API refusals live with their own tests.
describe 'Suspended teams' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team(name: 'Acme')
    @holder = Person.create(name: 'Owner', email: 'owner@acme.co')
    TeamMembership.create(team_id: @team.id, person_id: @holder.id, working: false)
    @team.update(creator_id: @holder.id)
    @worker = add_person(name: 'Worker')
    create_map
  end

  it 'lets everyone in while the team is not suspended' do
    assert_equal 200, driver.visit_team_dashboard(@team).status
  end

  it 'sends a working member to the team list' do
    suspend_team

    resp = driver.visit_team_dashboard(@team)

    assert_equal '/teams', URI.parse(resp['Location']).path
  end

  it 'keeps the map pages closed' do
    suspend_team

    resp = driver.visit_map(@map)

    assert_equal '/teams', URI.parse(resp['Location']).path
  end

  it 'sends the account holder to the link the suspension names' do
    suspend_team(message: 'Your trial ended.', link: '/billing/plans')
    login_as(@holder)

    resp = driver.visit_team_dashboard(@team)

    assert_equal '/billing/plans', URI.parse(resp['Location']).path
  end

  it 'sends the account holder to the account page when no link is named' do
    suspend_team
    login_as(@holder)

    resp = driver.visit_team_dashboard(@team)

    assert_equal "/teams/#{@team.id}/account", URI.parse(resp['Location']).path
  end

  it 'lets the account holder export the team data' do
    suspend_team
    login_as(@holder)

    resp = driver.get "/teams/#{@team.id}/account/export"

    assert_equal 200, resp.status
    assert_includes resp.content_type, 'application/json'
  end

  it 'lets the account holder reach the page that deletes the team' do
    suspend_team
    login_as(@holder)

    assert_equal 200, driver.get("/teams/#{@team.id}/account/delete").status
  end

  it 'keeps the CI Monitor open' do
    suspend_team

    assert_equal 200, visit_monitor(@team).status
  end
end
