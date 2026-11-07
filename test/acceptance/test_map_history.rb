# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Map history tab' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    @persona = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task = create_task('Sign up', under_activity: @activity)
    @story = create_story('Register', under_task: @task)
  end

  it 'shows history link in subnav' do
    visit_map

    assert_page_includes("/maps/#{@map.id}/history")
  end

  it 'renders history page with entity names' do
    resp = driver.visit_map_history(@map)

    assert_equal 200, resp.status
    assert_includes resp.body, 'Register'
    assert_includes resp.body, 'Sign up'
    assert_includes resp.body, 'Onboarding'
    assert_includes resp.body, 'Customer'
  end

  it 'shows map rename event' do
    driver.submit_map_rename(@map, name: 'Renamed Map')

    resp = driver.visit_map_history(@map)

    assert_includes resp.body, 'Renamed Map'
    assert_includes resp.body, 'renamed'
  end

  it 'describes actions using EventPresenter' do
    @bob = add_person(name: 'Bob', email: 'bob@acme.co')
    assign_person(@story, person: @bob)

    resp = driver.visit_map_history(@map)

    assert_includes resp.body, 'assigned Bob'
  end

  it 'resolves slice and task names from event state' do
    slice = create_release_slice('Sprint 1')
    move_story_to_slice(@story, release_slice_id: slice.id)

    resp = driver.visit_map_history(@map)

    assert_includes resp.body, 'Sprint 1'
    refute_includes resp.body, 'unknown'
  end

  it 'shows events in reverse chronological order' do
    @bob = add_person(name: 'Bob', email: 'bob@acme.co')
    assign_person(@story, person: @bob)

    resp = driver.visit_map_history(@map)

    body = resp.body
    assign_pos = body.index('assigned Bob')
    create_pos = body.index('created')

    refute_nil assign_pos
    refute_nil create_pos
    assert_operator assign_pos, :<, create_pos, 'Expected newest events first'
  end

  it 'shows actor name for each event' do
    resp = driver.visit_map_history(@map)

    assert_includes resp.body, 'Alice'
  end

  it 'does not show events from other maps' do
    other_map = Map.create(name: 'Other', team_id: @team.id, position: 99)
    RecordEvent.call(
      actor_id:    @alice.actor_id,
      entity:      @activity,
      action:      'created',
      map_id:      other_map.id,
      after_state: { name: 'Other Act' }
    )

    resp = driver.visit_map_history(@map)

    refute_includes resp.body, 'Other Act'
  end

  it 'shows Load more link when more events exist' do
    resp = driver.visit_map_history(@map, per_page: 2)

    assert_shown('history-load-more', resp.body)
    assert_includes resp.body, 'before='
  end

  it 'does not show Load more when all events fit' do
    resp = driver.visit_map_history(@map)

    refute_shown('history-load-more', resp.body)
  end

  it 'paginates with before cursor' do
    events = Event.where(map_id: @map.id).order(Sequel.desc(:event_no)).all
    cursor = events[1].event_no

    resp = driver.visit_map_history(@map, before: cursor)

    assert_equal 200, resp.status

    table = resp.body.split('history-table').last

    refute_includes table, 'Register'
    refute_includes table, 'Sign up'
    assert_includes table, 'Onboarding'
  end

  it 'shows entity name from event state when entity was deleted' do
    slice = create_release_slice('Sprint 1')
    driver.submit_delete_release_slice(@map, slice)

    resp = driver.visit_map_history(@map)

    assert_includes resp.body, 'Sprint 1'
    assert_includes resp.body, 'deleted'
  end
end
