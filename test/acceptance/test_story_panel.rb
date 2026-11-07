# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Story panel' do
  include MainlineDSL

  before do
    setup_team(name: 'Acme')
    @alice = add_person(name: 'Alice')
    create_map(name: 'Onboarding')
    persona  = create_persona('User')
    activity = create_activity('Sign up', for_personas: [persona])
    task     = create_task('Register', under_activity: activity)
    @story   = create_story('Fill form', under_task: task)
  end

  it 'returns edit form content without layout' do
    visit_story_panel(@story)

    assert_page_includes 'Fill form'
    refute_page_includes '<nav>'
  end

  it 'card route returns story card with current data' do
    @story.update(decoupling_strategy: 'flag', decoupling_label: 'FF_ONBOARD')

    visit_story_card(@story)

    assert_page_includes 'Fill form'
    assert_page_includes 'FF'
    refute_page_includes '<nav>'
  end

  it 'card renders clickable copy button for short ID' do
    visit_story_card(@story)

    body = page_body

    assert_includes body, 'data-test-id="card-copy-id"'
    assert_includes body, "data-story-id=\"#{@story.id}\""
    assert_includes body, @story.id[0, 8].upcase
  end
end
