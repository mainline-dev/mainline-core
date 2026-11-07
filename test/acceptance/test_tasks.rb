# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Tasks' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
  end

  it 'returns 404 for a non-UUID task id' do
    err = assert_raises(RuntimeError) { driver.get "/maps/#{@map.id}/tasks/b3404700/edit" }

    assert_match(/404/, err.message)
  end

  it 'creates a task under an activity' do
    visitor = create_persona('Visitor')
    browse  = create_activity('Browse', for_personas: [visitor])
    create_task('Search products', under_activity: browse)

    assert_map_shows 'Search products'
  end

  it 'requires a name' do
    visitor = create_persona('Visitor')
    browse  = create_activity('Browse', for_personas: [visitor])

    submit_create_task(name: '', activity_id: browse.id)

    assert_equal 0, Task.where(map_id: @map.id).count
    assert_error_shown
  end

  it 'rejects a task name over 100 characters' do
    visitor = create_persona('Visitor')
    browse  = create_activity('Browse', for_personas: [visitor])

    submit_create_task(name: 'x' * 101, activity_id: browse.id)

    assert_equal 0, Task.where(map_id: @map.id).count
    assert_error_shown
  end

  it 'rejects a non-existent activity' do
    submit_create_task(name: 'Orphan', activity_id: SecureRandom.uuid)

    assert_equal 0, Task.where(map_id: @map.id).count
    assert_error_shown
  end
end

describe 'Tasks - Archive' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @task = create_task('Search', under_activity: @browse)
  end

  it 'archives a task with no stories' do
    archive_task(@task)

    @task.reload

    refute_nil @task.archived_at
    assert_event_recorded(entity: @task, action: 'archived')
  end

  it 'refuses to archive a task that has stories' do
    create_story('Find things', under_task: @task)

    archive_task(@task)

    @task.reload

    assert_nil @task.archived_at
  end

  it 'shows archive link on map for empty tasks' do
    visit_map

    assert_includes page_body, "data-test-id=\"archive-task-#{@task.id}\"",
      'Expected archive link for empty task'
  end

  it 'hides archive link on map for tasks with stories' do
    create_story('Find things', under_task: @task)

    visit_map

    refute_includes page_body, "data-test-id=\"archive-task-#{@task.id}\"",
      'Expected no archive link for task with stories'
  end
end

describe 'Tasks - Edit' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @shop = create_activity('Shop', for_personas: [@visitor])
    @task = create_task('Search', under_activity: @browse)
  end

  it 'shows pre-filled edit form' do
    visit_edit_task(@task)

    assert_page_includes('Search')
  end

  it 'updates the name' do
    submit_edit_task(@task, name: 'Find', activity_id: @browse.id)

    @task.reload

    assert_equal 'Find', @task.name

    event = assert_event_recorded(entity: @task, action: 'edited')

    assert_equal 'Search', event.before_state['name']
    assert_equal 'Find', event.after_state['name']
  end

  it 'moves task to another activity' do
    submit_edit_task(@task, name: 'Search', activity_id: @shop.id)

    @task.reload

    assert_equal @shop.id, @task.activity_id
  end

  it 'moves task into activity that already has tasks' do
    existing = create_task('Pay', under_activity: @shop)
    submit_edit_task(@task, name: 'Search', activity_id: @shop.id)

    @task.reload

    assert_equal @shop.id, @task.activity_id
    assert_operator @task.position, :>, existing.position
  end

  it 'requires a name' do
    submit_edit_task(@task, name: '', activity_id: @browse.id)

    assert_error_shown

    @task.reload

    assert_equal 'Search', @task.name
  end

  it 'rejects an edit name over 100 characters' do
    submit_edit_task(@task, name: 'x' * 101, activity_id: @browse.id)

    @task.reload

    assert_equal 'Search', @task.name
    assert_error_shown
  end

  it 'rejects a non-existent activity' do
    submit_edit_task(@task, name: 'Search', activity_id: SecureRandom.uuid)

    @task.reload

    assert_equal @browse.id, @task.activity_id
    assert_error_shown
  end
end

describe 'Tasks - Reorder' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @shop = create_activity('Shop', for_personas: [@visitor])
    @task_a = create_task('Search', under_activity: @browse)
    @task_b = create_task('Filter', under_activity: @browse)
    @task_c = create_task('Sort', under_activity: @browse)
  end

  it 'reorders tasks within an activity' do
    reorder_tasks(@browse, task_ids: [@task_c.id, @task_b.id, @task_a.id])

    @task_a.reload
    @task_b.reload
    @task_c.reload

    assert_operator @task_c.position, :<, @task_b.position
    assert_operator @task_b.position, :<, @task_a.position
  end

  it 'moves a task to another activity' do
    reorder_tasks(@shop, task_ids: [@task_a.id])

    @task_a.reload

    assert_equal @shop.id, @task_a.activity_id
    assert_event_recorded(entity: @task_a, action: 'task_moved')
  end

  it 'rejects reorder containing an archived task' do
    @task_b.update(archived_at: Time.now)

    resp = reorder_tasks(@browse, task_ids: [@task_b.id, @task_a.id])

    assert_equal 422, resp.status
  end

  it 'rejects reorder on a locked map' do
    lock_map

    resp = reorder_tasks(@browse, task_ids: [@task_c.id, @task_b.id, @task_a.id])

    assert_equal 422, resp.status

    @task_a.reload

    assert_operator @task_a.position, :<, @task_b.reload.position
  end

  it 'records reorder events with before/after positions' do
    old_pos_a = @task_a.position

    reorder_tasks(@browse, task_ids: [@task_c.id, @task_b.id, @task_a.id])

    event = assert_event_recorded(entity: @task_a, action: 'reordered')

    assert_equal old_pos_a, event.before_state['position']
    refute_equal old_pos_a, event.after_state['position']
  end

  it 'moves a task into an activity that has an archived task at same position' do
    @task_a.update(activity_id: @shop.id)
    DB[:tasks].where(id: @task_a.id).update(position: 1000, archived_at: Time.now)

    reorder_tasks(@shop, task_ids: [@task_b.id])

    @task_b.reload

    assert_equal @shop.id, @task_b.activity_id
  end
end
