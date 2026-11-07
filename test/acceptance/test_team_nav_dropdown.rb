# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Team nav dropdown' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
  end

  it 'team breadcrumb has dropdown with admin links' do
    create_map
    visit_map

    body = page_body

    assert_includes body, 'nav-team-trigger'
    assert_includes body, "/teams/#{@team.id}/members"
    assert_includes body, '/settings'
    assert_includes body, "/teams/#{@team.id}/webhook"
  end

  it 'shows Account link for creator' do
    @team.update(creator_id: @alice.id)
    create_map
    visit_map

    body = page_body

    assert_includes body, "/teams/#{@team.id}/account"
  end

  it 'hides Account link for non-creator' do
    bob = add_person(name: 'Bob', email: 'bob@acme.co')
    @team.update(creator_id: bob.id)
    create_map
    visit_map

    body = page_body

    refute_includes body, "/teams/#{@team.id}/account"
  end

  it 'has Switch team and New team links' do
    create_map
    visit_map

    body = page_body

    assert_includes body, 'href="/teams"'
    assert_includes body, 'href="/teams/new"'
  end

  it 'Alice Chen menu does not have Teams link' do
    create_map
    visit_map

    body = page_body
    menu_start = body.index('nav-person-menu')
    menu_end = body.index('</div>', menu_start + 1)
    person_menu = body[menu_start..menu_end]

    refute_includes person_menu, '>Teams</a>'
  end
end

describe 'Team show page - maps only' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
  end

  it 'does not have Team section heading' do
    visit_team_dashboard

    body = page_body

    refute_includes body, '>Team</h2>'
  end

  it 'does not have Deploy Webhook section heading' do
    visit_team_dashboard

    body = page_body

    refute_includes body, '>Deploy Webhook</h2>'
  end

  it 'still shows maps section' do
    create_map(name: 'Onboarding')

    visit_team_dashboard

    assert_page_includes('Onboarding')
    assert_page_includes('data-test-id="map-onboarding"')
  end
end
