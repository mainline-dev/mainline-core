# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Happy path smoke (browser)' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map(name: 'Product')
    persona  = create_persona('Customer')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story_a = create_story('Find products', under_task: task)
    @story_b = create_story('Filter results', under_task: task)
    assign_person(@story_a, person: @alice)
    assign_person(@story_a, person: @bob)
    deploy_story(@story_a)
    release_story(@story_a)
    assign_person(@story_b, person: @alice)
    assign_person(@story_b, person: @bob)
    deploy_story(@story_b)
  end

  it 'walks through the full product from map to all views' do
    use_browser!

    # Map
    driver.visit_map(@map)

    assert_selector '.map-grid'
    assert_selector '.activity-header', text: /Browse/i
    assert_selector '.task-col', text: 'Search'
    assert_selector '.story-card'

    # Active filter
    find('[data-test-id="toggle-active-only"]').click

    assert_selector '.story-card', text: 'Filter results'

    # Team dashboard via nav
    click_on 'Acme'

    assert_text 'Acme'
    assert_text 'Product'

    # Teamwork: Pairing Matrix (nav dropdown)
    find('.nav-dropdown-trigger', text: 'Teamwork').hover
    click_on 'Pairing Matrix'

    assert_selector '.nav-breadcrumb', text: 'Teamwork'
    assert_text 'Alice'
    assert_text 'Bob'

    # Teamwork: Ensemble tab
    click_on 'Ensemble'

    assert_selector '.nav-breadcrumb', text: 'Teamwork'

    # Teamwork: Solo tab
    click_on 'Solo'

    assert_selector '.nav-breadcrumb', text: 'Teamwork'

    # Flow: Cumulative Flow (nav dropdown)
    find('.nav-dropdown-trigger', text: 'Flow').hover
    click_on 'Cumulative Flow'

    assert_selector '.nav-breadcrumb', text: 'Cumulative Flow'

    # Flow: Throughput
    click_on 'Throughput'

    assert_selector '.nav-breadcrumb', text: 'Throughput'

    # Flow: Lead Time
    click_on 'Lead Time'

    assert_selector '.nav-breadcrumb', text: 'Lead Time'

    # Inventory (nav link)
    click_on 'Inventory'

    assert_selector '.nav-breadcrumb', text: 'Inventory'
    assert_text 'Filter results'

    # Story history
    driver.visit_story_history(@map, @story_a)

    assert_text 'released'
  end
end
