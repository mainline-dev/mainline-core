# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Release a story' do
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
  end

  it 'releases an active story and clears assignments' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)

    release_story(@story)

    @story.refresh

    assert_equal 'released', @story.status
    refute_nil @story.released_at
    assert_equal 0, StoryAssignment.where(story_id: @story.id).count
    assert_event_recorded(entity: @story, action: 'released')
    assert_event_recorded(entity: @story, action: 'person_unassigned')
  end

  it 'shows released label on map' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)

    visit_map

    assert_page_includes('released')
  end

  it 'cannot release an active story with zero deploys' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    driver.submit_release(@map, @story)

    @story.refresh

    assert_equal 'active', @story.status
    assert_nil @story.released_at
  end

  it 'cannot release a planned story' do
    driver.submit_release(@map, @story)

    @story.refresh

    assert_equal 'planned', @story.status
    assert_nil @story.released_at
  end

  it 'release is terminal - no further assignment changes' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)

    assign_person(@story, person: @alice)

    @story.refresh

    assert_equal 'released', @story.status
  end
end
