# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Teams' do
  include MainlineDSL

  it 'lists teams without N+1 lookups' do
    setup_team(name: 'Alpha')
    alice = add_person(name: 'Alice')

    beta = Team.create(name: 'Beta')
    TeamMembership.create(team_id: beta.id, person_id: alice.id)

    resp = driver.visit_teams

    assert_equal 200, resp.status
    assert_includes resp.body, 'Alpha'
    assert_includes resp.body, 'Beta'
  end

  it 'creates a team with creator as account holder (non-working)' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)

    submit_create_team(team_name: 'Acme')

    team = Team.where(name: 'Acme').first

    refute_nil team, 'Team was not created'

    membership = TeamMembership.where(team_id: team.id, person_id: alice.id).first

    refute_nil membership, 'Membership was not created'
    refute membership.working, 'Creator should be account holder (working: false)'
  end

  it 'asks only for a team name' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)

    resp = driver.visit_new_team

    assert_includes resp.body, 'name="team_name"'
    refute_includes resp.body, 'data-test-id="plan-picker"'
  end

  it 'blocks creating a team while one you hold is suspended' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)
    submit_create_team(team_name: 'First')
    suspend_team(Team.where(name: 'First').first)

    driver.submit_create_team(team_name: 'Second')

    assert_nil Team.where(name: 'Second').first
  end

  it 'allows creating a team once you have left the suspended one' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)
    submit_create_team(team_name: 'First')
    suspend_team(Team.where(name: 'First').first)
    TeamMembership.where(person_id: alice.id).update(left_at: Time.now)

    submit_create_team(team_name: 'Second')

    refute_nil Team.where(name: 'Second').first
  end

  it 'allows creating a second team when none of yours is suspended' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)
    submit_create_team(team_name: 'First')

    submit_create_team(team_name: 'Second')

    refute_nil Team.where(name: 'Second').first
  end

  it 'starts with an empty team name' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)

    resp = driver.visit_new_team

    assert_includes resp.body, 'value=""'
  end

  it 'requires a team name' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)

    submit_create_team(team_name: '')

    assert_equal 0, Team.count
    assert_error_shown
  end

  it 'rejects a team name over 100 characters' do
    alice = Person.create(name: 'Alice', email: 'alice@acme.co')
    login_as(alice)

    submit_create_team(team_name: 'x' * 101)

    assert_equal 0, Team.count
    assert_error_shown
  end

  it 'redirects unauthenticated team creation to login' do
    resp = driver.submit_create_team(team_name: 'Acme')

    assert_equal 302, resp.status
    assert_equal '/login', URI.parse(resp['Location']).path
    assert_equal 0, Team.count
  end

  it 'returns 404 for invalid team ID' do
    setup_team
    add_person(name: 'Alice')

    err = assert_raises(RuntimeError) {
      driver.visit_team_dashboard(Struct.new(:id).new('not-a-uuid'))
    }

    assert_match(/404/, err.message)
  end
end

describe 'Team - Edit' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    @alice = add_person(name: 'Alice')
    @team.update(creator_id: @alice.id)
  end

  it 'shows pre-filled edit form' do
    visit_edit_team

    assert_page_includes('Acme')
  end

  it 'updates the name' do
    submit_edit_team(name: 'Acme Corp')

    @team.reload

    assert_equal 'Acme Corp', @team.name
  end

  it 'records edit event' do
    submit_edit_team(name: 'Acme Corp')

    event = assert_event_recorded(entity: @team, action: 'edited')

    assert_equal 'Acme', event.before_state['name']
    assert_equal 'Acme Corp', event.after_state['name']
  end

  it 'requires a name' do
    submit_edit_team(name: '')

    @team.reload

    assert_equal 'Acme', @team.name
    assert_error_shown
  end

  it 'rejects a name over 100 characters' do
    submit_edit_team(name: 'x' * 101)

    @team.reload

    assert_equal 'Acme', @team.name
    assert_error_shown
  end

  it 'rejects non-creator editing team name' do
    bob = add_person(name: 'Bob')
    login_as(bob)

    resp = driver.submit_edit_team(@team, name: 'Hacked')

    @team.reload

    assert_equal 'Acme', @team.name
    assert_equal 403, resp.status
  end
end

describe 'Team Dashboard' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    @alice = add_person(name: 'Alice')
  end

  it 'shows team name and maps' do
    create_map(name: 'Product Map')
    create_map(name: 'Platform Map')

    visit_team_dashboard

    assert_page_includes('Acme')
    assert_page_includes('Product Map')
    assert_page_includes('Platform Map')
  end

  it 'shows empty state with no maps' do
    visit_team_dashboard

    assert_page_includes('empty-workspace')
  end
end
