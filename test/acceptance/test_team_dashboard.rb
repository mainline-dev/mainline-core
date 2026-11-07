# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Team dashboard' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    add_person(name: 'Alice', email: 'alice@acme.co')
  end

  it 'shows the team name' do
    visit_team_dashboard

    assert_page_includes('Acme')
  end

  it 'lists active maps' do
    create_map(name: 'Onboarding')
    create_map(name: 'Checkout')

    visit_team_dashboard

    assert_page_includes('Onboarding')
    assert_page_includes('Checkout')
  end

  it 'shows empty state when no maps' do
    visit_team_dashboard

    assert_page_includes('empty-workspace')
  end

  it 'shows activity and story counts on map cards' do
    create_map(name: 'Onboarding')
    persona = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task = create_task('Search', under_activity: activity)
    create_story('Find item', under_task: task)
    create_story('Filter results', under_task: task)

    visit_team_dashboard

    assert_page_includes('data-activities="1" data-stories="2"')
  end

  it 'shows active story count on map cards' do
    create_map(name: 'Onboarding')
    bob = add_person(name: 'Bob', email: 'bob@acme.co')
    persona = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task = create_task('Search', under_activity: activity)
    story = create_story('Find item', under_task: task)
    assign_person(story, person: bob)
    assign_person(story, person: Person.where(name: 'Alice').first)
    create_story('Planned one', under_task: task)

    visit_team_dashboard

    assert_page_includes('data-active="1"')
  end

  it 'shows last updated time on map cards' do
    create_map(name: 'Onboarding')
    persona = create_persona('User')
    create_activity('Browse', for_personas: [persona])

    visit_team_dashboard

    assert_page_includes('today')
  end

  it 'account holder sees account and members links' do
    @team.update(creator_id: Person.where(name: 'Alice').first.id)

    visit_team_dashboard

    body = page_body

    assert_includes body, "/teams/#{@team.id}/account"
    assert_includes body, "/teams/#{@team.id}/members"
  end

  it 'non-creator does not see account link' do
    bob = add_person(name: 'Bob', email: 'bob@acme.co')
    @team.update(creator_id: bob.id)

    visit_team_dashboard

    body = page_body

    refute_includes body, "/teams/#{@team.id}/account"
    assert_includes body, "/teams/#{@team.id}/members"
  end

  it 'shows nav links on map view' do
    create_map(name: 'Onboarding')
    persona = create_persona('User')
    create_activity('Browse', for_personas: [persona])
    visit_map

    body = page_body

    assert_includes body, "/teams/#{@team.id}/teamwork"
    assert_includes body, "/teams/#{@team.id}/flow"
    assert_includes body, "/teams/#{@team.id}/inventory"
  end
end
