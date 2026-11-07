# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Inventory' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    @task    = create_task('Search', under_activity: activity)
  end

  it 'shows deployed stories on inventory page' do
    story = create_story('Deployed feature', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)

    visit_inventory

    assert_page_includes('Deployed feature')
  end

  it 'shows summary counts' do
    story = create_story('In flight', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)

    visit_inventory

    assert_page_includes('data-test-id="inventory-in-flight" data-count="1"')
  end

  it 'excludes released stories' do
    story = create_story('Released feature', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_inventory

    refute_content_includes('Released feature')
  end

  it 'shows empty state when no inventory' do
    visit_inventory

    assert_shown('inventory-empty')
  end

  it 'shows band labels' do
    story = create_story('Band test', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)

    visit_inventory

    assert_page_includes('In flight')
  end

  it 'shows released stories with decoupling strategy in cleanup section' do
    story = create_story('Flagged feature', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    edit_story(story, title: story.title, task_id: story.task_id,
      decoupling_strategy: 'flag', decoupling_label: 'FF_SEARCH')
    release_story(story)

    visit_inventory

    assert_shown('inventory-cleanup')
    assert_page_includes('Flagged feature')
    assert_page_includes('FF')
  end

  it 'does not show released stories without decoupling in cleanup section' do
    story = create_story('Clean feature', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_inventory

    refute_shown('inventory-cleanup')
  end

  it 'links cleanup stories to their edit page' do
    story = create_story('Linked feature', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    edit_story(story, title: story.title, task_id: story.task_id,
      decoupling_strategy: 'bba', decoupling_label: 'BBA_LAYER')
    release_story(story)

    visit_inventory

    assert_page_includes("/stories/#{story.id}/edit")
  end
end
