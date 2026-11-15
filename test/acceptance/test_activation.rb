# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

# Once a team is past its first steps, one line on its page names the next
# thing to connect, in order: the Ticket Museum, GitHub, the deploy webhook,
# a coding agent. The line goes once everything is connected.
describe 'The next thing to connect' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    make_account_holder(@alice)
  end

  def release_a_story
    create_map(name: 'Shop')
    task = create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
    story = create_story('Shoppers can pay by card', under_task: task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)
  end

  def bring_in_the_backlog
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))
  end

  it 'says nothing while the team is on its first steps' do
    visit_team_page

    refute_shown('ladder')
  end

  it 'starts with the backlog once the first steps are done' do
    release_a_story

    visit_team_page

    assert_equal 'museum', next_to_connect
  end

  it 'moves on to GitHub once the backlog is in' do
    release_a_story
    bring_in_the_backlog

    visit_team_page

    assert_equal 'github', next_to_connect
  end

  it 'skips GitHub on an install without the CI Monitor' do
    release_a_story
    bring_in_the_backlog

    with_ci_monitor_off { visit_team_page }

    assert_equal 'webhook', next_to_connect
  end

  it 'moves on to the coding agent once the webhook has a token' do
    release_a_story
    bring_in_the_backlog
    connect_github
    generate_webhook_token

    visit_team_page

    assert_equal 'agent', next_to_connect
  end

  it 'goes once everything is connected' do
    release_a_story
    bring_in_the_backlog
    connect_github
    generate_webhook_token
    generate_mcp_token

    visit_team_page

    refute_shown('ladder')
  end
end
