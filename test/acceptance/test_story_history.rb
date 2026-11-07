# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Story history' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    @bob   = add_person(name: 'Bob',   email: 'bob@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
  end

  it 'shows created event with actor name' do
    story = create_story('Register account', under_task: @task)

    visit_story_history(story)

    assert_page_includes('created')
    assert_page_includes('Alice')
  end

  it 'shows assign and unassign events with person names' do
    story = create_story('Register account', under_task: @task)
    assignment = begin
      assign_person(story, person: @bob)
      StoryAssignment.where(story_id: story.id, person_id: @bob.id).first
    end

    unassign_person(story, assignment)

    visit_story_history(story)

    assert_page_includes('assigned')
    assert_page_includes('unassigned')
    assert_page_includes('Bob')
  end

  it 'shows release event' do
    story = create_story('Register account', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_story_history(story)

    assert_page_includes('released')
  end

  it 'shows archive event' do
    story = create_story('Register account', under_task: @task)
    archive_story(story)

    visit_story_history(story)

    assert_page_includes('archived')
  end

  it 'shows slice move event' do
    story = create_story('Register account', under_task: @task)
    slice = create_release_slice('Sprint 1')
    move_story_to_slice(story, release_slice_id: slice.id)

    visit_story_history(story)

    assert_page_includes('Sprint 1')
  end

  it 'shows from and to slices on slice change' do
    story = create_story('Register account', under_task: @task)
    sprint1 = create_release_slice('Sprint 1')
    sprint2 = create_release_slice('Sprint 2')
    move_story_to_slice(story, release_slice_id: sprint1.id)
    move_story_to_slice(story, release_slice_id: sprint2.id)

    visit_story_history(story)

    body = page_body

    assert_match(/Sprint 1[^<]*Sprint 2/, body)
  end

  it 'shows events latest first' do
    story = create_story('Register account', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_story_history(story)
    body = page_body

    created_pos  = body.index('created')
    assigned_pos = body.index('assigned')
    released_pos = body.index('released')

    refute_nil created_pos
    refute_nil assigned_pos
    refute_nil released_pos
    assert_operator released_pos, :<, assigned_pos, 'released should appear before assigned'
    assert_operator assigned_pos, :<, created_pos, 'assigned should appear before created'
  end

  it 'history link appears on map for planned story' do
    story = create_story('Register account', under_task: @task)
    visit_map

    assert_page_includes("/stories/#{story.id}/history")
  end

  it 'history link appears on map for active story' do
    story = create_story('Register account', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_map

    assert_page_includes("/stories/#{story.id}/history")
  end

  it 'history link appears on map for released story' do
    story = create_story('Register account', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_map

    assert_page_includes("/stories/#{story.id}/history")
  end
end
