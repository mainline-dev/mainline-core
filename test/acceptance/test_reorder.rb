# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Reorder stories within a task' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    create_map
    persona  = create_persona('Customer')
    activity = create_activity('Browse', for_personas: [persona])
    @task    = create_task('Search', under_activity: activity)
    @story_a = create_story('Story A', under_task: @task)
    @story_b = create_story('Story B', under_task: @task)
    @story_c = create_story('Story C', under_task: @task)
  end

  def story_order
    Story.where(task_id: @task.id).order(:position).select_map(:id)
  end

  it 'moves a story down one position' do
    resp = reorder_stories(@task,
      story_ids: [@story_b.id, @story_a.id, @story_c.id])

    assert_equal 200, resp.status
    assert_equal [@story_b.id, @story_a.id, @story_c.id], story_order
    assert_event_recorded(entity: @story_a, action: 'reordered')
    assert_event_recorded(entity: @story_b, action: 'reordered')
    assert_no_events_for(entity: @story_c, action: 'reordered')
  end

  it 'moves a story up one position' do
    resp = reorder_stories(@task,
      story_ids: [@story_b.id, @story_a.id, @story_c.id])

    assert_equal 200, resp.status
    assert_equal [@story_b.id, @story_a.id, @story_c.id], story_order
  end

  it 'moves a story to the end' do
    resp = reorder_stories(@task,
      story_ids: [@story_b.id, @story_c.id, @story_a.id])

    assert_equal 200, resp.status
    assert_equal [@story_b.id, @story_c.id, @story_a.id], story_order
    assert_event_recorded(entity: @story_a, action: 'reordered')
    assert_event_recorded(entity: @story_b, action: 'reordered')
    assert_event_recorded(entity: @story_c, action: 'reordered')
  end

  it 'moves a story to the start' do
    resp = reorder_stories(@task,
      story_ids: [@story_c.id, @story_a.id, @story_b.id])

    assert_equal 200, resp.status
    assert_equal [@story_c.id, @story_a.id, @story_b.id], story_order
    assert_event_recorded(entity: @story_a, action: 'reordered')
    assert_event_recorded(entity: @story_b, action: 'reordered')
    assert_event_recorded(entity: @story_c, action: 'reordered')
  end

  it 'handles no-op reorder with no events' do
    original = story_order
    resp = reorder_stories(@task, story_ids: original)

    assert_equal 200, resp.status
    assert_equal original, story_order
    assert_no_events_for(entity: @story_a, action: 'reordered')
    assert_no_events_for(entity: @story_b, action: 'reordered')
    assert_no_events_for(entity: @story_c, action: 'reordered')
  end
end

describe 'Move story to another task' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    persona    = create_persona('Customer')
    @activity  = create_activity('Browse', for_personas: [persona])
    @task_src  = create_task('Search', under_activity: @activity)
    @task_dest = create_task('Filter', under_activity: @activity)
    @story_a   = create_story('Story A', under_task: @task_src)
    @story_b   = create_story('Story B', under_task: @task_src)
    @story_x   = create_story('Story X', under_task: @task_dest)
  end

  it 'moves a story to another task via reorder endpoint' do
    resp = reorder_stories(@task_dest, story_ids: [@story_a.id, @story_x.id])

    assert_equal 200, resp.status

    @story_a.refresh

    assert_equal @task_dest.id, @story_a.task_id
    assert_event_recorded(entity: @story_a, action: 'task_changed')
  end

  it 'preserves position order in target task' do
    resp = reorder_stories(@task_dest, story_ids: [@story_a.id, @story_x.id])

    assert_equal 200, resp.status

    order = Story.where(task_id: @task_dest.id, archived_at: nil).order(:position).select_map(:id)

    assert_equal [@story_a.id, @story_x.id], order
  end

  it 'blocks moving a released story to another task' do
    assign_person(@story_a, person: @alice)
    bob = add_person(name: 'Bob')
    assign_person(@story_a, person: bob)
    deploy_story(@story_a)
    release_story(@story_a)

    resp = reorder_stories(@task_dest, story_ids: [@story_a.id])

    assert_equal 422, resp.status

    @story_a.refresh

    assert_equal @task_src.id, @story_a.task_id
  end

  it 'returns 422 for non-existent story ID' do
    resp = reorder_stories(@task_src, story_ids: [SecureRandom.uuid])

    assert_equal 422, resp.status
  end

  it 'returns 422 when moving released story to a different slice' do
    slice = create_release_slice('MVP')
    assign_person(@story_a, person: @alice)
    bob = add_person(name: 'Bob')
    assign_person(@story_a, person: bob)
    deploy_story(@story_a)
    release_story(@story_a)

    resp = reorder_stories(@task_src,
      story_ids: [@story_a.id], release_slice_id: slice.id)

    assert_equal 422, resp.status

    @story_a.refresh

    assert_nil @story_a.release_slice_id
  end

  it 'returns 422 for invalid slice ID' do
    resp = reorder_stories(@task_src,
      story_ids: [@story_a.id], release_slice_id: SecureRandom.uuid)

    assert_equal 422, resp.status
  end
end
