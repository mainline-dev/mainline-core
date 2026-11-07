# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Decoupling tag' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    create_map
    @persona  = create_persona('User')
    @activity = create_activity('Browse', for_personas: [@persona])
    @task     = create_task('Search', under_activity: @activity)
    @story    = create_story('Add search bar', under_task: @task)
  end

  it 'sets decoupling strategy and label via edit' do
    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: 'flag', decoupling_label: 'FF_SEARCH')

    @story.refresh

    assert_equal 'flag', @story.decoupling_strategy
    assert_equal 'FF_SEARCH', @story.decoupling_label
  end

  it 'sets strategy without label' do
    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: 'bba', decoupling_label: '')

    @story.refresh

    assert_equal 'bba', @story.decoupling_strategy
    assert_nil @story.decoupling_label
  end

  it 'clears decoupling strategy' do
    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: 'dark_launch', decoupling_label: 'DL_SEARCH')
    @story.refresh

    assert_equal 'dark_launch', @story.decoupling_strategy

    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: '', decoupling_label: '')
    @story.refresh

    assert_nil @story.decoupling_strategy
    assert_nil @story.decoupling_label
  end

  it 'ignores label when strategy is none' do
    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: '', decoupling_label: 'ORPHAN_LABEL')

    @story.refresh

    assert_nil @story.decoupling_strategy
    assert_nil @story.decoupling_label
  end

  it 'shows decoupling fields on edit form' do
    visit_edit_story(@story)

    body = page_body

    assert_includes body, 'decoupling_strategy'
    assert_includes body, 'decoupling_label'
  end

  it 'pre-selects current strategy on edit form' do
    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: 'flag', decoupling_label: 'FF_SEARCH')

    visit_edit_story(@story)

    body = page_body

    assert_includes body, 'FF_SEARCH'
  end

  it 'records decoupling change in event' do
    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: 'flag', decoupling_label: 'FF_SEARCH')

    event = Event.where(entity_id: @story.id, action: 'edited').order(:occurred_at).last

    after = JSON.parse(event.after_state.to_json)

    assert_equal 'flag', after['decoupling_strategy']
    assert_equal 'FF_SEARCH', after['decoupling_label']
  end

  it 'shows strategy badge on map card' do
    edit_story(@story, title: @story.title, task_id: @story.task_id,
      decoupling_strategy: 'flag', decoupling_label: 'FF_SEARCH')

    visit_map

    body = page_body

    assert_includes body, 'decoupling-pill'
    assert_includes body, 'FF'
  end

  it 'does not show badge when no strategy set' do
    visit_map

    body = page_body

    refute_includes body, 'decoupling-pill'
  end
end
