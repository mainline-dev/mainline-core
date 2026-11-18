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

  describe 'saying whether they will work on stories too' do
    before { someone_new_signs_in }

    it 'offers working on stories, ticked to start' do
      visit_new_team_form

      assert_predicate self, :working_on_stories_ticked?
    end

    it 'opens the maps to a creator who will work on stories' do
      start_a_team('Acme', working: true)
      create_map

      assert_predicate self, :map_opens?
    end

    it 'keeps the maps closed to a creator who will not, until they join' do
      start_a_team('Acme', working: false)
      create_map
      closed = !map_opens?
      join_as_working_member

      assert closed
      assert_predicate self, :map_opens?
    end

    it 'gives someone with no team yet no new-map form' do
      refute_predicate self, :new_map_form_offered?
    end

    it 'takes no new map from a creator who is not working on stories' do
      start_a_team('Acme', working: false)
      offered = new_map_form_offered?
      submit_create_map(name: 'Checkout')

      refute offered
      assert_empty map_names
    end

    it 'offers them joining on the first steps, where a new map would be' do
      start_a_team('Acme', working: false)
      visit_team_page

      assert_shown('first-run-join')
      refute_shown('first-run-new-map')
    end

    it 'offers a working creator a new map on the first steps' do
      start_a_team('Acme', working: true)
      visit_team_page

      assert_shown('first-run-new-map')
      refute_shown('first-run-join')
    end

    it 'keeps the choice when the form is refused' do
      start_a_team('', working: false)

      refute_predicate self, :working_on_stories_ticked?
    end
  end
end
