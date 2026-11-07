# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'First login landing' do
  include MainlineDSL

  it 'new team creator is working: false' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)
    submit_create_team(team_name: 'Acme')

    team = Team.where(name: 'Acme').first
    membership = TeamMembership.where(team_id: team.id, person_id: alice.id).first

    refute membership.working
  end

  it 'creator lands on workspace, not account page' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)

    resp = submit_create_team(team_name: 'Acme')

    assert_predicate resp, :redirect?
    team = Team.where(name: 'Acme').first

    assert_equal "/teams/#{team.id}", URI.parse(resp['Location']).path
  end

  it 'non-working creator sees workspace without bounce' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)
    submit_create_team(team_name: 'Acme')
    team = Team.where(name: 'Acme').first

    resp = driver.visit_team_dashboard(team)

    assert_equal 200, resp.status
  end

  it 'non-working creator sees join link in empty state' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)
    submit_create_team(team_name: 'Acme')
    team = Team.where(name: 'Acme').first

    resp = driver.visit_team_dashboard(team)

    assert_includes resp.body, 'data-test-id="join-working"'
    assert_includes resp.body, 'empty-workspace'
  end

  it 'clicking join makes creator a working member' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)
    submit_create_team(team_name: 'Acme')
    team = Team.where(name: 'Acme').first

    driver.submit_join_team(team)

    membership = TeamMembership.where(team_id: team.id, person_id: alice.id).first

    assert membership.working
  end
end
