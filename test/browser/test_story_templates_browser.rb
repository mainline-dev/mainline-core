# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Story templates (browser)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
  end

  it 'creates story via card template in real browser' do
    use_browser!
    driver.submit_create_story_from_template(@map, {
      task_id:  @task.id,
      template: 'card',
      persona:  'Customer',
      action:   'signs up'
    })

    story = Story.where(map_id: @map.id).first

    refute_nil story
    assert_equal 'Customer signs up', story.title
  end

  it 'creates story via connextra template in real browser' do
    use_browser!
    driver.submit_create_story_from_template(@map, {
      task_id:  @task.id,
      template: 'connextra',
      role:     'Returning Customer',
      goal:     'reorder with one click',
      benefit:  'I save time'
    })

    story = Story.where(map_id: @map.id).first

    refute_nil story
    assert_equal 'As a Returning Customer, I want to reorder with one click, so that I save time', story.title
  end

  it 'creates story via behaviour template in real browser' do
    use_browser!
    driver.submit_create_story_from_template(@map, {
      task_id:  @task.id,
      template: 'behaviour',
      context:  'viewing order history',
      persona:  'Returning Customer',
      action:   'reorder with one click'
    })

    story = Story.where(map_id: @map.id).first

    refute_nil story
    assert_equal 'When viewing order history, Returning Customer can reorder with one click', story.title
  end
end
