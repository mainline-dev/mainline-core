# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'
require_relative '../dsl/mainline_file'

# A new team's page lists its first steps, each ticked off by what the team
# has done, until its first story is released.
describe 'First steps on the team page' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
  end

  after do
    back_to_today
  end

  def a_task
    create_map(name: 'Shop')
    create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
  end

  it 'shows a new team its first steps, none of them done' do
    visit_team_page

    assert_shown('first-run')
    assert_empty first_steps_done
  end

  it 'starts the map from a new map' do
    visit_team_page

    follow_museum_link('first-run-new-map')

    assert_shown('new-map-form')
  end

  it 'starts the map from an import' do
    visit_team_page

    follow_museum_link('first-run-import')

    assert_shown('museum-import-form')
  end

  it 'ticks off starting the map once the team has a map' do
    create_map(name: 'Shop')

    visit_team_page

    assert_equal %w[map], first_steps_done
    refute_shown('first-run-new-map')
    refute_shown('first-run-import')
  end

  it 'ticks off starting the map once a Jira CSV is in the museum' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))

    visit_team_page

    assert_equal %w[map], first_steps_done
  end

  it 'ticks off starting the map once a Mainline file is in the museum' do
    import_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }))

    visit_team_page

    assert_equal %w[map], first_steps_done
  end

  it 'ticks off pulling what is real' do
    task = a_task
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))
    promote_museum_item('SHOP-1', title: 'Shoppers can pay by card', task: task)

    visit_team_page

    assert_equal %w[map promote], first_steps_done
  end

  it 'ticks off the first release slice and the first story started' do
    task = a_task
    create_release_slice('First release')
    story = create_story('Shoppers can pay by card', under_task: task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_team_page

    assert_equal %w[map slice start], first_steps_done
  end

  it 'ticks off the coding agent once the team has an MCP token' do
    make_account_holder(@alice)
    generate_mcp_token

    visit_team_page

    assert_equal %w[agent], first_steps_done
  end

  it 'ticks off checking back once the museum can say how much was never pulled' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))
    days_pass(90)
    login_as(@alice)

    visit_team_page

    assert_equal %w[map figure], first_steps_done
  end

  it 'leaves the first steps behind once the first story is released' do
    story = create_story('Shoppers can pay by card', under_task: a_task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    pass_a_scenario(story)
    release_story(story)

    visit_team_page

    refute_shown('first-run')
  end
end
