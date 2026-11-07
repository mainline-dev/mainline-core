# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Archive a story' do
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

  it 'archives a planned story' do
    archive_story(@story)

    @story.refresh

    refute_nil @story.archived_at
    assert_event_recorded(entity: @story, action: 'archived')
  end

  it 'archived story disappears from map' do
    archive_story(@story)

    visit_map

    refute_content_includes('Register')
  end

  it 'cannot archive a story with people assigned' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    archive_story(@story)

    @story.refresh

    assert_nil @story.archived_at
    assert_equal 2, StoryAssignment.where(story_id: @story.id).count
  end

  it 'map shows archive button for planned story' do
    visit_map

    assert_page_includes('data-test-id="archive-register"')
  end

  it 'map does not show archive button for released story' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)

    visit_map

    refute_page_includes('data-test-id="archive-register"')
  end

  it 'cannot archive a released story' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)

    archive_story(@story)

    @story.refresh

    assert_nil @story.archived_at
  end
end
