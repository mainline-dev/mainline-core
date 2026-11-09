# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Activities' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
  end

  it 'returns 404 for a non-UUID activity id' do
    err = assert_raises(RuntimeError) { driver.get "/maps/#{@map.id}/activities/b3404700/edit" }

    assert_match(/404/, err.message)
  end

  it 'creates an activity with a persona' do
    visitor = create_persona('Visitor')
    create_activity('Browse catalogue', for_personas: [visitor])

    assert_map_shows 'Browse catalogue'
  end

  it 'requires at least one persona' do
    submit_create_activity(name: 'Orphan', persona_ids: [])

    assert_equal(0, BypassRLS.call { Activity.where(map_id: @map.id).count })
  end

  it 'allows multiple personas' do
    visitor   = create_persona('New Visitor')
    returning = create_persona('Returning Customer')

    browse = create_activity('Browse catalogue',
      for_personas: [visitor, returning])

    links = ActivityPersona.where(activity_id: browse.id).count

    assert_equal 2, links
  end

  it 'rejects non-existent personas' do
    submit_create_activity(name: 'Orphan', persona_ids: [SecureRandom.uuid])

    assert_equal(0, BypassRLS.call { Activity.where(map_id: @map.id).count })
    assert_error_shown
  end

  it 'requires a name' do
    persona = create_persona('Visitor')

    submit_create_activity(name: '', persona_ids: [persona.id])

    assert_equal(0, BypassRLS.call { Activity.where(map_id: @map.id).count })
    assert_error_shown
  end

  it 'rejects a name over 100 characters' do
    persona = create_persona('Visitor')

    submit_create_activity(name: 'x' * 101, persona_ids: [persona.id])

    assert_equal(0, BypassRLS.call { Activity.where(map_id: @map.id).count })
    assert_error_shown
  end
end

describe 'Activities - Archive' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @activity = create_activity('Browse', for_personas: [@visitor])
  end

  it 'archives an activity with no tasks' do
    archive_activity(@activity)

    @activity.reload

    refute_nil @activity.archived_at
    assert_event_recorded(entity: @activity, action: 'archived')
  end

  it 'refuses to archive an activity that has tasks' do
    create_task('Search', under_activity: @activity)

    archive_activity(@activity)

    @activity.reload

    assert_nil @activity.archived_at
  end

  it 'archives an activity when all tasks are archived' do
    task = create_task('Search', under_activity: @activity)
    task.update(archived_at: Time.now)

    archive_activity(@activity)

    @activity.reload

    refute_nil @activity.archived_at
  end

  it 'shows archive button on map for empty activity' do
    visit_map

    assert_includes page_body, "data-test-id=\"archive-activity-#{@activity.id}\""
  end

  it 'hides archive button on map for activity with tasks' do
    create_task('Search', under_activity: @activity)

    visit_map

    refute_includes page_body, "data-test-id=\"archive-activity-#{@activity.id}\""
  end

  it 'archived activity disappears from map' do
    archive_activity(@activity)

    visit_map

    refute_content_includes('Browse')
  end
end

describe 'Activities - Edit' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @customer = create_persona('Customer')
    @activity = create_activity('Browse', for_personas: [@visitor])
  end

  it 'shows pre-filled edit form' do
    visit_edit_activity(@activity)

    assert_page_includes('Browse')
  end

  it 'updates the name' do
    submit_edit_activity(@activity, name: 'Shop', persona_ids: [@visitor.id])

    @activity.reload

    assert_equal 'Shop', @activity.name

    event = assert_event_recorded(entity: @activity, action: 'edited')

    assert_equal 'Browse', event.before_state['name']
    assert_equal 'Shop', event.after_state['name']
  end

  it 'updates persona associations' do
    submit_edit_activity(@activity, name: 'Browse', persona_ids: [@visitor.id, @customer.id])

    links = ActivityPersona.where(activity_id: @activity.id).all

    assert_equal 2, links.length
  end

  it 'removes a persona association' do
    submit_edit_activity(@activity, name: 'Browse', persona_ids: [@customer.id])

    links = ActivityPersona.where(activity_id: @activity.id).all

    assert_equal 1, links.length
    assert_equal @customer.id, links.first.persona_id
  end

  it 'requires a name' do
    submit_edit_activity(@activity, name: '', persona_ids: [@visitor.id])

    assert_error_shown

    @activity.reload

    assert_equal 'Browse', @activity.name
  end

  it 'rejects an edit name over 100 characters' do
    submit_edit_activity(@activity, name: 'x' * 101, persona_ids: [@visitor.id])

    @activity.reload

    assert_equal 'Browse', @activity.name
    assert_error_shown
  end

  it 'requires at least one persona' do
    submit_edit_activity(@activity, name: 'Browse', persona_ids: [])

    assert_error_shown
  end

  it 'rejects non-existent personas on edit' do
    submit_edit_activity(@activity, name: 'Browse', persona_ids: [SecureRandom.uuid])

    @activity.reload

    assert_equal 'Browse', @activity.name

    links = ActivityPersona.where(activity_id: @activity.id).select_map(:persona_id)

    assert_equal [@visitor.id], links
    assert_error_shown
  end

  it 'preserves link to archived persona when editing activity' do
    @visitor.update(archived_at: Time.now)

    submit_edit_activity(@activity, name: 'Browse', persona_ids: [@customer.id])

    links = ActivityPersona.where(activity_id: @activity.id).select_map(:persona_id)

    assert_includes links, @visitor.id
    assert_includes links, @customer.id
  end

  it 'rejects editing activity from another map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 9000)
    foreign = Activity.create(map_id: other_map.id, team_id: @team.id, name: 'Foreign', position: 1000)

    assert_raises(RuntimeError, '404 - Not Found') do
      driver.visit_edit_activity(@map, foreign)
    end
  end

  it 'has disabled save button' do
    visit_edit_activity(@activity)

    assert_includes page_body, 'disabled'
  end

  it 'returns inline edit form via HTMX GET' do
    resp = driver.htmx_get_edit_activity(@map, @activity)

    refute_predicate resp, :redirect?
    refute_includes resp.body, '<!DOCTYPE'
    assert_includes resp.body, 'Browse'
    assert_includes resp.body, 'disabled'
  end

  it 'returns item after HTMX save' do
    resp = driver.htmx_edit_activity(@map, @activity, name: 'Shop', persona_ids: [@visitor.id])

    refute_predicate resp, :redirect?
    assert_includes resp.body, 'data-id'
    assert_includes resp.body, 'Shop'

    @activity.reload

    assert_equal 'Shop', @activity.name
  end

  it 'htmx save returns updated history via OOB' do
    resp = driver.htmx_edit_activity(@map, @activity, name: 'Shop', persona_ids: [@visitor.id])

    assert_includes resp.body, 'hx-swap-oob'
    assert_includes resp.body, 'renamed'
  end

  it 'returns inline form with errors on HTMX validation failure' do
    resp = driver.htmx_edit_activity(@map, @activity, name: '', persona_ids: [@visitor.id])

    refute_predicate resp, :redirect?
    assert_error_shown(resp.body)
    assert_includes resp.body, 'disabled'

    @activity.reload

    assert_equal 'Browse', @activity.name
  end

  it 'returns item partial on HTMX cancel' do
    resp = driver.htmx_get_activity(map: @map, activity: @activity)

    refute_predicate resp, :redirect?
    refute_includes resp.body, '<!DOCTYPE'
    assert_includes resp.body, 'Browse'
    assert_includes resp.body, 'data-id'
    assert_includes resp.body, "/activities/#{@activity.id}/edit"
  end
end

describe 'Activities - Reorder' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @activity_a = create_activity('Browse', for_personas: [@visitor])
    @activity_b = create_activity('Shop', for_personas: [@visitor])
    @activity_c = create_activity('Checkout', for_personas: [@visitor])
  end

  it 'moves an activity to the right' do
    old_pos_a = @activity_a.position
    old_pos_b = @activity_b.position

    move_activity(@activity_a, direction: 'right')

    @activity_a.reload
    @activity_b.reload

    assert_equal old_pos_b, @activity_a.position
    assert_equal old_pos_a, @activity_b.position
  end

  it 'moves an activity to the left' do
    old_pos_a = @activity_a.position
    old_pos_b = @activity_b.position

    move_activity(@activity_b, direction: 'left')

    @activity_a.reload
    @activity_b.reload

    assert_equal old_pos_b, @activity_a.position
    assert_equal old_pos_a, @activity_b.position
  end

  it 'rejects move on a locked map' do
    lock_map
    old_pos_a = @activity_a.position

    move_activity(@activity_a, direction: 'right')

    @activity_a.reload

    assert_equal old_pos_a, @activity_a.position
  end

  it 'records reorder events on both activities' do
    move_activity(@activity_a, direction: 'right')

    assert_event_recorded(entity: @activity_a, action: 'reordered')
    assert_event_recorded(entity: @activity_b, action: 'reordered')
  end

  it 'ignores move-right on the rightmost activity' do
    old_pos_c = @activity_c.position

    move_activity(@activity_c, direction: 'right')

    @activity_c.reload

    assert_equal old_pos_c, @activity_c.position
  end

  it 'ignores move-left on the leftmost activity' do
    old_pos_a = @activity_a.position

    move_activity(@activity_a, direction: 'left')

    @activity_a.reload

    assert_equal old_pos_a, @activity_a.position
  end

  it 'reorders activities via drag' do
    reorder_activities(activity_ids: [@activity_c.id, @activity_a.id, @activity_b.id])

    ordered = Activity.where(map_id: @map.id).order(:position).select_map(:name)

    assert_equal %w[Checkout Browse Shop], ordered
  end

  it 'rejects drag reorder on a locked map' do
    lock_map

    resp = reorder_activities(activity_ids: [@activity_c.id, @activity_a.id, @activity_b.id])

    assert_equal 422, resp.status
  end

  it 'rejects drag reorder with unknown activity' do
    resp = reorder_activities(activity_ids: [SecureRandom.uuid])

    assert_equal 422, resp.status
  end
end

describe 'Activities - History sidebar' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
  end

  it 'shows activity history on index page' do
    create_activity('Browse', for_personas: [@visitor])

    visit_activities

    assert_page_includes('data-test-id="activity-history"')
    assert_page_includes('Browse')
    assert_page_includes('Alice')
  end

  it 'shows empty state when no activity events' do
    visit_activities

    body = page_body

    refute_includes body, 'section-title">History'
  end

  it 'shows all events when 20 or fewer' do
    activity = create_activity('Browse', for_personas: [@visitor])

    5.times do |i|
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: activity, action: 'edited',
        before_state: { name: "v#{i}" }, after_state: { name: "v#{i + 1}" }
      )
    end

    visit_activities

    body = page_body

    refute_shown('history-show-all', body)
  end

  it 'limits history to 20 most recent and shows Show all link' do
    activity = create_activity('Browse', for_personas: [@visitor])

    25.times do |i|
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: activity, action: 'edited',
        before_state: { name: "v#{i}" }, after_state: { name: "v#{i + 1}" }
      )
    end

    visit_activities

    body = page_body

    assert_shown('history-show-all', body)
    assert_includes body, 'v25'
    refute_includes body, '&quot;v0&quot;'
  end

  it 'show-all returns full history' do
    activity = create_activity('Browse', for_personas: [@visitor])

    25.times do |i|
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: activity, action: 'edited',
        before_state: { name: "v#{i}" }, after_state: { name: "v#{i + 1}" }
      )
    end

    driver.visit_activity_history(@map)

    body = page_body

    assert_includes body, 'v25'
    assert_includes body, '&quot;v0&quot;'
    refute_shown('history-show-all', body)
  end
end
