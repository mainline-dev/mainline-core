# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Maps' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'creates a map' do
    submit_create_map(name: 'Product Map')

    map = Map.where(team_id: @team.id, name: 'Product Map').first

    refute_nil map
    assert_event_recorded(entity: map, action: 'created')
  end

  it 'requires a name' do
    submit_create_map(name: '')

    assert_equal(0, BypassRLS.call { Map.where(team_id: @team.id).count })
    assert_error_shown
  end

  it 'rejects a map name over 100 characters' do
    submit_create_map(name: 'x' * 101)

    assert_equal(0, BypassRLS.call { Map.where(team_id: @team.id).count })
    assert_error_shown
  end

  it 'redirects to teams when map team is not found' do
    create_map
    Team.stub(:[], nil) do
      visit_map_by_id(@map.id)

      assert_equal 302, driver.last_response.status
    end
  end

  it 'empty map shows tutorial hint' do
    create_map

    visit_map

    assert_page_includes('getting-started-hint')
    assert_page_includes('/docs/tutorial')
  end

  it 'calls a map with nothing on it empty, and does not blame a filter' do
    create_map

    visit_map

    assert_shown('map-empty')
    refute_shown('map-no-match')
  end

  it 'map with activities but no stories shows tutorial hint' do
    create_map
    persona = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    create_task('Search', under_activity: activity)

    visit_map

    assert_page_includes('getting-started-hint')
  end

  it 'map with stories does not show tutorial hint' do
    create_map
    persona = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task = create_task('Search', under_activity: activity)
    create_story('Find item', under_task: task)

    visit_map

    refute_page_includes('getting-started-hint')
  end

  it 'locks a map to hide creation and edit UI' do
    create_map
    persona = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task = create_task('Search', under_activity: activity)
    create_story('Find item', under_task: task)

    lock_map

    visit_map

    refute_page_includes("/maps/#{@map.id}/tasks/new")
    refute_page_includes("/maps/#{@map.id}/stories/new")
    refute_page_includes('drag-handle')
    refute_page_includes("stories/#{Story.first.id}/edit")
    refute_page_includes("tasks/#{task.id}/edit")
    refute_page_includes("activities/#{activity.id}/edit")
    assert_page_includes('data-test-id="lock-map" data-locked="true"')
    assert_shown('inline-assign-trigger')
    assert_page_includes("/maps/#{@map.id}/history")
  end

  it 'unlocks a locked map to restore creation UI' do
    create_map
    persona = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    create_task('Search', under_activity: activity)

    lock_map
    lock_map

    visit_map

    assert_page_includes("/maps/#{@map.id}/tasks/new")
    assert_page_includes("/maps/#{@map.id}/stories/new")
    assert_page_includes('data-test-id="lock-map" data-locked="false"')
  end
end

describe 'Maps - Edit' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map(name: 'Product Map')
  end

  it 'shows pre-filled edit form' do
    visit_edit_map

    assert_page_includes('Product Map')
  end

  it 'updates the name' do
    submit_edit_map(name: 'Renamed Map')

    @map.reload

    assert_equal 'Renamed Map', @map.name

    event = assert_event_recorded(entity: @map, action: 'edited')

    assert_equal 'Product Map', event.before_state['name']
    assert_equal 'Renamed Map', event.after_state['name']
  end

  it 'requires a name' do
    submit_edit_map(name: '')

    assert_error_shown

    @map.reload

    assert_equal 'Product Map', @map.name
  end

  it 'rejects an edit name over 100 characters' do
    submit_edit_map(name: 'x' * 101)

    @map.reload

    assert_equal 'Product Map', @map.name
    assert_error_shown
  end

  it 'renames map via inline edit' do
    submit_edit_map(name: 'Renamed Map')

    @map.reload

    assert_equal 'Renamed Map', @map.name
  end
end

describe 'Maps - Filters' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    @persona = create_persona('User')
    @activity = create_activity('Browse', for_personas: [@persona])
    @task = create_task('Search', under_activity: @activity)
  end

  it 'active filter shows only active stories' do
    create_story('Planned one', under_task: @task)
    active_story = create_story('Active one', under_task: @task)
    assign_person(active_story, person: @alice)
    assign_person(active_story, person: @bob)

    active_story.reload

    assert_equal 'active', active_story.status

    visit_map_active

    assert_page_includes('Active one')
    refute_page_includes('Planned one')
  end

  it 'slices filter groups stories by release slice' do
    slice = create_release_slice('MVP')
    story = create_story('Sliced story', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)

    create_story('Unsliced story', under_task: @task)

    visit_map_slices

    assert_page_includes('MVP')
    assert_page_includes('Sliced story')
    assert_page_includes('Unsliced story')
  end

  it 'combined active+slices filter shows only active stories grouped by slice' do
    slice = create_release_slice('MVP')
    active_story = create_story('Active sliced', under_task: @task)
    assign_person(active_story, person: @alice)
    assign_person(active_story, person: @bob)
    move_story_to_slice(active_story, release_slice_id: slice.id)

    planned_story = create_story('Planned sliced', under_task: @task)
    move_story_to_slice(planned_story, release_slice_id: slice.id)

    visit_map_active_slices

    assert_content_includes('Active sliced')
    refute_content_includes('Planned sliced')
  end
end

describe 'Maps - Archive' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map(name: 'Old Map')
  end

  it 'archives a map and it no longer appears on team dashboard' do
    archive_map(@map)

    resp = driver.visit_team_dashboard(@team)

    refute_includes resp.body, 'data-test-id="map-old-map"'
  end

  it 'records an event when archiving' do
    archive_map(@map)

    event = Event.where(entity_type: 'map', action: 'archived').first

    refute_nil event
    assert_equal @map.id, event.entity_id
  end

  it 'allows creating a new map with the same name after archiving' do
    archive_map(@map)

    driver.submit_create_map(name: 'Old Map')

    active = Map.where(team_id: @team.id, archived_at: nil, name: 'Old Map').count

    assert_equal 1, active
  end

  it 'archived map is not accessible' do
    archive_map(@map)

    err = assert_raises(RuntimeError) { driver.get "/maps/#{@map.id}" }

    assert_includes err.message, '404'
  end

  it 'blocks archiving when map has active activities' do
    @persona = create_persona('Customer')
    create_activity('Onboarding', for_personas: [@persona])

    archive_map(@map)

    @map.refresh

    assert_nil @map.archived_at
  end

  it 'blocks archiving when map has active personas' do
    create_persona('Customer')

    archive_map(@map)

    @map.refresh

    assert_nil @map.archived_at
  end

  it 'archives when all content is archived' do
    @persona = create_persona('Customer')
    archive_persona(@persona)

    archive_map(@map)

    @map.refresh

    refute_nil @map.archived_at
  end

  it 'does not show the archive option when the map has active content' do
    create_persona('Customer')

    visit_map

    refute_page_includes 'data-test-id="archive-map"'
  end

  it 'shows the archive option when the map is empty' do
    visit_map

    assert_page_includes 'data-test-id="archive-map"'
  end
end
