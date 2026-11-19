# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'
require_relative '../dsl/mainline_file'

# A new team's page lists its first steps, each ticked off by what the team
# has done, until its first story is released. Once the four steps every team
# needs are done, the list folds away: into one line saying when the museum
# will have its figure, for a team with a Jira backlog, and into nothing for a
# team without one, since no figure is coming.
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

  # The four steps every team needs: a map, something promoted, a release
  # slice and a story started. Connecting a coding agent is left out.
  def do_the_needed_steps(backlog:)
    task = a_task
    if backlog == :jira
      import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))
      promote_museum_item('SHOP-1', title: 'Shoppers can pay by card', task: task)
    else
      import_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }))
      promote_museum_item('RB-1', title: 'Two people can save at once', task: task)
    end
    create_release_slice('First release')
    story = create_story('Shoppers can pay by gift card', under_task: task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
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

  it 'ticks off the coding agent once anyone on the team makes a personal token for it' do
    login_as(@bob)
    create_personal_token(name: 'laptop', teams: [@team], expires_on: Date.today + 30)

    visit_team_page

    assert_equal %w[agent], first_steps_done
  end

  it 'leads the coding agent step to a personal token for this team' do
    add_member(@alice, another_team('Mobile'))

    visit_team_page
    follow_link('first-run-coding-agent')

    assert_equal({ 'Mobile' => false, 'Test Team' => true }, token_teams_shown)
  end

  it 'ticks off checking back once the museum can say how much was never pulled' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))
    days_pass(90)
    login_as(@alice)

    visit_team_page

    assert_equal %w[map figure], first_steps_done
  end

  it 'makes no promise of a figure to a team that has brought in no Jira backlog' do
    import_mainline_file(MainlineFileFixture.json({ key: 'RB-1' }))

    visit_team_page

    assert_equal %w[map promote slice start agent], first_steps_listed
    assert_nil figure_due_on
  end

  it 'says when the museum will have its figure, 90 days after the Jira backlog came in' do
    import_jira_csv(JiraExport.csv({ key: 'SHOP-1', id: '1', summary: 'Pay by card' }))

    visit_team_page

    assert_equal %w[map promote slice start agent figure], first_steps_listed
    assert_equal Time.now.utc.to_date + 90, figure_due_on
  end

  it 'keeps the steps open while one of the four needed steps is still to do' do
    create_map(name: 'Shop')

    visit_team_page

    refute_predicate self, :first_steps_folded?
  end

  it 'folds the steps into one line with the date once the four needed steps are done, coding agent or not' do
    do_the_needed_steps(backlog: :jira)

    visit_team_page

    assert_predicate self, :first_steps_folded?
    assert_equal Time.now.utc.to_date + 90, figure_due_on
    assert_equal %w[map promote slice start], first_steps_done
  end

  it 'gives the figure on day 90, with a way to the museum' do
    do_the_needed_steps(backlog: :jira)
    days_pass(90)
    login_as(@alice)

    visit_team_page

    assert_equal 0, figure_shown
    follow_link('first-run-museum')

    assert_equal 0, never_pulled_percent
  end

  it 'leaves the page to the maps once the needed steps are done and no figure is coming' do
    do_the_needed_steps(backlog: :specification)

    visit_team_page

    refute_shown('first-run')
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
