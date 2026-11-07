# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Active filter' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    @bob   = add_person(name: 'Bob',   email: 'bob@acme.co')
    @carol = add_person(name: 'Carol', email: 'carol@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @active_story  = create_story('Register', under_task: @task)
    @planned_story = create_story('Verify email', under_task: @task)

    assign_person(@active_story, person: @alice)
    assign_person(@active_story, person: @bob)
  end

  it 'without param shows all stories' do
    visit_map

    assert_page_includes('Register')
    assert_page_includes('Verify email')
  end

  it 'active filter hides planned stories' do
    visit_map_active

    refute_page_includes('Verify email')
  end

  it 'active filter shows active stories' do
    visit_map_active

    assert_page_includes('Register')
  end

  it 'active filter hides released stories' do
    deploy_story(@active_story)
    release_story(@active_story)

    @released_story = @active_story

    assign_person(@planned_story, person: @alice)
    assign_person(@planned_story, person: @carol)

    visit_map_active

    assert_page_includes('Verify email')
    refute_page_includes('Register')
  end

  it 'active filter hides tasks with no active stories' do
    @task2 = create_task('Browse', under_activity: @activity)
    create_story('Search products', under_task: @task2)

    visit_map_active

    assert_page_includes('Sign up')
    refute_page_includes('Browse')
  end

  it 'active filter hides activities with no active stories' do
    @activity2 = create_activity('Checkout', for_personas: [@persona])
    @task2 = create_task('Pay', under_activity: @activity2)
    create_story('Enter card', under_task: @task2)

    visit_map_active

    assert_page_includes('Onboarding')
    refute_page_includes('Checkout')
  end

  it 'active + slices filters combine' do
    slice = create_release_slice('MVP')
    move_story_to_slice(@active_story, release_slice_id: slice.id)

    visit_map_active_slices

    assert_page_includes('Register')
    refute_page_includes('Verify email')
    assert_page_includes('MVP')
    assert_page_includes('slice-header')
  end

  it 'slices view shows active-only toggle preserving slices param' do
    create_release_slice('MVP')

    visit_map_slices

    assert_page_includes('active=1')
    assert_page_includes('slices=1')
  end

  it 'active view shows slices toggle preserving active param' do
    create_release_slice('MVP')

    visit_map_active

    assert_page_includes('slices=1')
    assert_page_includes('active=1')
  end
end
