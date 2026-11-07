# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Map card actions (browser)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    persona  = create_persona('Customer')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story = create_story('Find things', under_task: task)
  end

  it 'archive requires two clicks to confirm' do
    use_browser!
    driver.visit_map(@map)

    find('[data-test-id="card-kebab"] summary').click
    btn = find('[data-test-id="archive-find-things"]')

    assert_equal 'Archive', btn.text

    btn.click

    assert_equal 'confirm?', btn.text

    sleep 3.5
    btn = find('[data-test-id="archive-find-things"]')

    assert_equal 'Archive', btn.text
  end

  it 'archive confirm removes the story from the grid' do
    use_browser!
    driver.visit_map(@map)

    find('[data-test-id="card-kebab"] summary').click
    btn = find('[data-test-id="archive-find-things"]')
    btn.click
    btn.click

    assert_no_selector '.card-body', text: 'Find things', wait: 5
  end

  it 'deploy shows flash toast via HTMX' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    use_browser!
    driver.visit_map(@map)

    find('[data-test-id="card-kebab"] summary').click
    btn = find('[data-test-id="deploy-find-things"]')
    btn.click
    btn.click

    assert_selector '.flash', text: /deployed/i, wait: 5
  end

  it 'release shows flash toast via HTMX' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)

    use_browser!
    driver.visit_map(@map)

    find('[data-test-id="card-kebab"] summary').click
    btn = find('[data-test-id="release-find-things"]')
    btn.click
    btn.click

    assert_selector '.flash', text: /released/i, wait: 5
  end
end
