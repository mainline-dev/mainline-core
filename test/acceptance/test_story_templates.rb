# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Story templates' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
  end

  it 'creates a story with connextra template' do
    submit_create_story_from_template(
      task_id:  @task.id,
      template: 'connextra',
      role:     'Returning Customer',
      goal:     'reorder with one click',
      benefit:  'I save time'
    )

    story = Story.where(map_id: @map.id).first

    refute_nil story
    assert_equal 'As a Returning Customer, I want to reorder with one click, so that I save time', story.title
    assert_event_recorded(entity: story, action: 'created')
  end

  it 'creates a story with behaviour template' do
    submit_create_story_from_template(
      task_id:  @task.id,
      template: 'behaviour',
      context:  'viewing order history',
      persona:  'Returning Customer',
      action:   'reorder with one click'
    )

    story = Story.where(map_id: @map.id).first

    refute_nil story
    assert_equal 'When viewing order history, Returning Customer can reorder with one click', story.title
  end

  it 'creates a story with card template' do
    submit_create_story_from_template(
      task_id:  @task.id,
      template: 'card',
      persona:  'Returning Customer',
      action:   'reorders previous purchase'
    )

    story = Story.where(map_id: @map.id).first

    refute_nil story
    assert_equal 'Returning Customer reorders previous purchase', story.title
  end

  it 'rejects connextra with missing fields' do
    submit_create_story_from_template(
      task_id:  @task.id,
      template: 'connextra',
      role:     'Customer',
      goal:     '',
      benefit:  ''
    )

    assert_equal(0, BypassRLS.call { Story.where(map_id: @map.id).count })
  end

  it 'rejects unknown template' do
    submit_create_story_from_template(
      task_id:  @task.id,
      template: 'nonsense',
      role:     'Foo'
    )

    assert_equal(0, BypassRLS.call { Story.where(map_id: @map.id).count })
  end

  it 'shows template on map card' do
    submit_create_story_from_template(
      task_id:  @task.id,
      template: 'card',
      persona:  'Customer',
      action:   'signs up'
    )

    visit_map

    assert_page_includes('Customer signs up')
  end

  it 'description field is not used' do
    submit_create_story_from_template(
      task_id:  @task.id,
      template: 'card',
      persona:  'Customer',
      action:   'signs up'
    )

    story = Story.where(map_id: @map.id).first

    assert_equal '', story.description
  end
end
