# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Hide released stories' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    @bob   = add_person(name: 'Bob',   email: 'bob@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @story    = create_story('Register', under_task: @task)
    @planned  = create_story('Verify email', under_task: @task)

    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)
  end

  it 'shows released stories by default' do
    visit_map

    assert_page_includes('Register')
    assert_page_includes('Verify email')
  end

  it 'hides released stories when hide_released is on' do
    driver.visit_map_with_params(@map, hide_released: 1)

    refute_content_includes('Register')
    assert_content_includes('Verify email')
  end

  it 'toggle preserves active and slices params' do
    resp = driver.visit_map_with_params(@map, active: 0, slices: 0)

    assert_includes resp.body, 'hide_released=1'
  end

  it 'persists hide_released preference' do
    driver.visit_map_with_params(@map, hide_released: 1)
    resp = driver.visit_map(@map)

    assert_equal 200, resp.status
    refute_includes resp.body, 'Register'
  end

  it 'keeps tasks and activities visible when all stories are released' do
    resp = driver.visit_map_with_params(@map, hide_released: 1)

    assert_equal 200, resp.status
    assert_includes resp.body, 'Sign up'
    assert_includes resp.body, 'Onboarding'
  end

  it 'combines with active filter' do
    @carol = add_person(name: 'Carol', email: 'carol@acme.co')
    active_story = create_story('OAuth login', under_task: @task)
    assign_person(active_story, person: @alice)
    assign_person(active_story, person: @carol)

    resp = driver.visit_map_with_params(@map, active: 1, hide_released: 1)

    assert_equal 200, resp.status
    assert_includes resp.body, 'OAuth login'
    refute_includes resp.body, 'Register'
    refute_includes resp.body, 'Verify email'
  end
end
