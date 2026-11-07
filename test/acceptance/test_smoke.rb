# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Smoke test: happy path end-to-end' do
  include MainlineDSL

  it 'builds a map, works stories, reorders, archives, and releases' do
    setup_team
    alice = add_person(name: 'Alice')
    bob   = add_person(name: 'Bob')
    create_map

    customer = create_persona('Customer')
    browse   = create_activity('Browse catalogue', for_personas: [customer])
    search   = create_task('Search products', under_activity: browse)

    story_a = create_story('Keyword search', under_task: search)
    story_b = create_story('Filter by price', under_task: search)
    story_c = create_story('Sort results', under_task: search)

    assert_map_shows 'Customer'
    assert_map_shows 'Browse catalogue'
    assert_map_shows 'Search products'
    assert_map_shows 'Keyword search'
    assert_map_shows 'Filter by price'
    assert_map_shows 'Sort results'

    # Reorder: move story_c to the top
    resp = reorder_stories(search,
      story_ids: [story_c.id, story_a.id, story_b.id])

    assert_equal 200, resp.status
    order = Story.where(task_id: search.id, archived_at: nil).order(:position).select_map(:id)

    assert_equal [story_c.id, story_a.id, story_b.id], order

    # Assign Alice + Bob to story_a -> activates (paired)
    assign_person(story_a, person: alice)
    assign_person(story_a, person: bob)

    assert_equal 'active', story_a.refresh.status

    # Deploy + Release story_a
    deploy_story(story_a)
    release_story(story_a)

    assert_equal 'released', story_a.refresh.status
    assert_equal 0, StoryAssignment.where(story_id: story_a.id).count

    # Archive story_b (no assignments, still planned)
    archive_story(story_b)

    refute_nil story_b.refresh.archived_at
    refute_nil story_b.refresh.position

    # Create a new story after archiving
    create_story('Autocomplete', under_task: search)

    assert_map_shows 'Autocomplete'

    # Reorder remaining visible stories (story_a released, story_b archived, story_c + story_d active)
    # JS sends ALL non-archived IDs in container order, including released
    visible = Story.where(task_id: search.id, archived_at: nil).order(:position).select_map(:id)
    resp = reorder_stories(search,
      story_ids: visible.reverse)

    assert_equal 200, resp.status

    # Verify map still renders
    assert_map_shows 'Sort results'
    assert_map_shows 'Autocomplete'
    assert_map_does_not_show 'Filter by price'

    # Verify event trail is complete
    events = Event.where(map_id: @map.id).all
    actions = events.map(&:action).uniq.sort

    assert_includes actions, 'created'
    assert_includes actions, 'reordered'
    assert_includes actions, 'person_assigned'
    assert_includes actions, 'activated'
    assert_includes actions, 'released'
    assert_includes actions, 'person_unassigned'
    assert_includes actions, 'archived'
  end
end
