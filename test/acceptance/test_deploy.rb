# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Deploy story' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story   = create_story('Show results', under_task: task)
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    @story.refresh
  end

  it 'deploys an active story' do
    deploy_story(@story)

    @story.refresh

    assert_equal 1, @story.deploy_count
    refute_nil @story.first_deployed_at
    refute_nil @story.last_deployed_at
    assert_event_recorded(entity: @story, action: 'deployed')
  end

  it 'increments deploy_count on subsequent deploys' do
    deploy_story(@story)
    deploy_story(@story)

    @story.refresh

    assert_equal 2, @story.deploy_count
    assert_operator @story.first_deployed_at, :<=, @story.last_deployed_at
  end

  it 'rejects deploy of a planned story' do
    planned = create_story('Not started', under_task: Task.where(map_id: @map.id).first)

    deploy_story(planned)

    planned.refresh

    assert_equal 0, planned.deploy_count
    assert_no_events_for(entity: planned, action: 'deployed')
  end

  it 'returns flash in HX-Trigger header on HTMX deploy' do
    resp = driver.htmx_deploy_story(@map, @story)

    trigger = resp['HX-Trigger']

    refute_nil trigger
    assert_includes trigger, 'deployed'
  end

  it 'returns flash in HX-Trigger header on HTMX release' do
    deploy_story(@story)

    resp = driver.htmx_release_story(@map, @story)

    trigger = resp['HX-Trigger']

    refute_nil trigger
    assert_equal 'notice', JSON.parse(trigger)['showFlash']['type']
  end

  it 'returns error flash in HX-Trigger on HTMX release without deploy' do
    resp = driver.htmx_release_story(@map, @story)

    trigger = resp['HX-Trigger']

    refute_nil trigger
    assert_equal 'error', JSON.parse(trigger)['showFlash']['type']
  end

  it 'records manual deploy under person actor' do
    deploy_story(@story)

    event = Event.where(entity_id: @story.id, action: 'deployed').first

    assert_equal @alice.actor_id, event.actor_id
  end

  it 'rejects deploy of a released story' do
    deploy_story(@story)
    release_story(@story)
    @story.refresh

    deploy_story(@story)

    @story.refresh

    assert_equal 1, @story.deploy_count
  end
end
