# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Slice filter' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    @bob   = add_person(name: 'Bob',   email: 'bob@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @other_activity = create_activity('Billing', for_personas: [@persona])
    @other_task     = create_task('Pay invoice', under_activity: @other_activity)
    @sliced_story   = create_story('Register', under_task: @task)
    @unsliced_story = create_story('Verify email', under_task: @task)
    @other_story    = create_story('Enter card', under_task: @other_task)
    @slice = create_release_slice('MVP')
    @other_slice = create_release_slice('Later')
    move_story_to_slice(@sliced_story, release_slice_id: @slice.id)
    move_story_to_slice(@other_story, release_slice_id: @other_slice.id)
  end

  it 'without slice filter shows all stories' do
    visit_map

    assert_page_includes('Register')
    assert_page_includes('Verify email')
    assert_page_includes('Enter card')
  end

  it 'does not call the map empty when the slice it is filtered to has no stories' do
    empty = create_release_slice('Someday')

    driver.visit_map_with_params(@map, slice_filter: empty.id)

    refute_shown('map-empty')
    assert_shown('map-no-match')
  end

  it 'slice filter shows only stories in that slice' do
    driver.visit_map_with_params(@map, slice_filter: @slice.id)

    assert_page_includes('Register')
    refute_page_includes('Verify email')
    refute_page_includes('Enter card')
  end

  it 'slice filter hides tasks and activities with no stories in the slice' do
    driver.visit_map_with_params(@map, slice_filter: @slice.id)

    refute_page_includes('Pay invoice')
    refute_page_includes('Billing')
  end

  it 'slice filter persists across plain visits' do
    driver.visit_map_with_params(@map, slice_filter: @slice.id)

    visit_map

    refute_page_includes('Enter card')
    assert_page_includes('Register')
  end

  it 'empty slice filter param clears the filter' do
    driver.visit_map_with_params(@map, slice_filter: @slice.id)

    driver.visit_map_with_params(@map, slice_filter: '')

    assert_page_includes('Enter card')
  end

  it 'unknown slice id shows all stories' do
    driver.visit_map_with_params(@map, slice_filter: '00000000-0000-0000-0000-000000000000')

    assert_page_includes('Register')
    assert_page_includes('Enter card')
  end

  it 'map shows a slice filter control when slices exist' do
    visit_map

    assert_page_includes('data-test-id="slice-filter"')
  end

  it 'no slice filter control without slices' do
    map_b = Map.create(team_id: @team.id, name: 'Empty Map', position: 2000)

    visit_map_by_id(map_b.id)

    refute_page_includes('data-test-id="slice-filter"')
  end

  it 'dropdown trigger is not a link that clears the filter' do
    driver.visit_map_with_params(@map, slice_filter: @slice.id)

    assert_match(/<details[^>]*data-test-id="slice-filter"/, driver.last_response.body)
    assert_match(/<summary[^>]*class="filter-toggle/, driver.last_response.body)
  end

  it 'params without slice_filter key preserve the saved slice filter' do
    driver.visit_map_with_params(@map, slice_filter: @slice.id)

    driver.visit_map_with_params(@map, active: '0')

    refute_page_includes('data-test-id="story-title-enter-card"')
    assert_page_includes('data-test-id="story-title-register"')
  end

  it 'slice_filter-only params preserve the other saved filters' do
    driver.visit_map_with_params(@map, active: '1')

    driver.visit_map_with_params(@map, slice_filter: @slice.id)

    assert_page_includes('data-test-id="toggle-active-only" aria-pressed="true"')
  end

  it 'slice filter with hide released hides tasks whose slice stories are all released' do
    assign_person(@sliced_story, person: @alice)
    assign_person(@sliced_story, person: @bob)
    deploy_story(@sliced_story)
    release_story(@sliced_story)

    driver.visit_map_with_params(@map, slice_filter: @slice.id, hide_released: '1')

    refute_page_includes('Sign up')
    refute_page_includes('Onboarding')
  end

  it 'sliced view with slice filter shows only that slice band' do
    driver.visit_map_with_params(@map, slice_filter: @slice.id, slices: '1')

    assert_page_includes('slice-label">MVP')
    refute_page_includes('slice-label">Later')
  end

  it 'slice filter combines with active only' do
    assign_person(@sliced_story, person: @alice)
    assign_person(@sliced_story, person: @bob)
    another = create_story('Also in slice', under_task: @task)
    move_story_to_slice(another, release_slice_id: @slice.id)

    driver.visit_map_with_params(@map, slice_filter: @slice.id, active: '1')

    assert_page_includes('data-test-id="story-title-register"')
    refute_page_includes('data-test-id="story-title-also-in-slice"')
  end
end
