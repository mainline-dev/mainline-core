# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Map view preferences' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @search = create_task('Search', under_activity: @browse)
    @story = create_story('Find things', under_task: @search)
  end

  it 'redirects preserve active filter' do
    visit_map_active

    archive_story(@story)
    driver.follow_redirect! if driver.redirected?

    assert_includes driver.last_response.body, 'data-test-id="toggle-active-only" aria-pressed="true"'
  end

  it 'redirects preserve slices view' do
    create_release_slice('MVP')
    visit_map_slices

    archive_story(@story)
    driver.follow_redirect! if driver.redirected?

    assert_includes driver.last_response.body, 'data-test-id="toggle-slices" aria-pressed="true"'
  end

  it 'toggle off is persisted' do
    visit_map_active

    driver.visit_map_with_params(@map, active: '0', slices: '0')

    archive_story(@story)
    driver.follow_redirect! if driver.redirected?

    assert_page_includes 'data-test-id="toggle-active-only" aria-pressed="false"'
  end

  it 'prefs are per-map' do
    map_b = Map.create(team_id: @team.id, name: 'Other Map', position: 2000)

    visit_map_active

    driver.visit_map(map_b)

    assert driver.response_includes?('data-test-id="toggle-active-only" aria-pressed="false"'),
      'Map B should default to no active filter'
  end

  it 'prefs are per-person' do
    visit_map_active

    bob = add_person(name: 'Bob')
    login_as(bob)

    visit_map

    assert_page_includes 'data-test-id="toggle-active-only" aria-pressed="false"'
  end
end
