# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

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

  it 'ticks off bringing in the backlog and pulling what is real' do
    task = a_task
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))
    promote_museum_item('SHOP-1', title: 'Shoppers can pay by card', task: task)

    visit_team_page

    assert_equal %w[import promote], first_steps_done
  end

  it 'ticks off the first release slice and the first story started' do
    task = a_task
    create_release_slice('First release')
    story = create_story('Shoppers can pay by card', under_task: task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_team_page

    assert_equal %w[slice start], first_steps_done
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

    assert_equal %w[import figure], first_steps_done
  end

  it 'leaves the first steps behind once the first story is released' do
    story = create_story('Shoppers can pay by card', under_task: a_task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_team_page

    refute_shown('first-run')
  end
end
