# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Release slices' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
  end

  it 'returns 404 for a non-UUID slice id' do
    err = assert_raises(RuntimeError) { driver.get "/maps/#{@map.id}/release_slices/b3404700/edit_name" }

    assert_match(/404/, err.message)
  end

  it 'creates a release slice' do
    slice = create_release_slice('MVP')

    assert_equal @map.id, slice.map_id
    refute_nil slice.position
  end

  it 'shows slice name on slices view' do
    create_release_slice('MVP')

    visit_map_slices

    assert_page_includes('MVP')
  end

  it 'switches between normal and slice views' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)

    visit_map

    refute_page_includes('slice-header')

    visit_map_slices

    assert_page_includes('slice-header')

    driver.visit_map_with_params(@map, active: '0', slices: '0')

    refute_page_includes('slice-header')
  end

  it 'cannot create slice without name' do
    submit_create_release_slice(name: '')

    assert_equal(0, BypassRLS.call { ReleaseSlice.where(map_id: @map.id).count })
  end

  it 'rejects a slice name over 100 characters' do
    submit_create_release_slice(name: 'x' * 101)

    assert_equal(0, BypassRLS.call { ReleaseSlice.where(map_id: @map.id).count })
    assert_error_shown
  end

  it 'moves a story into a slice' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)

    move_story_to_slice(story, release_slice_id: slice.id)

    story.refresh

    assert_equal slice.id, story.release_slice_id
    assert_event_recorded(entity: story, action: 'slice_changed')
  end

  it 'moves a story back to unsliced' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)

    move_story_to_slice(story, release_slice_id: slice.id)
    move_story_to_slice(story, release_slice_id: '')

    story.refresh

    assert_nil story.release_slice_id
  end

  it 'cannot move a released story' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    assign_person(story, person: @alice)
    bob = add_person(name: 'Bob', email: 'bob@acme.co')
    assign_person(story, person: bob)
    deploy_story(story)
    release_story(story)

    move_story_to_slice(story, release_slice_id: slice.id)

    story.refresh

    assert_nil story.release_slice_id
  end

  it 'default map view shows all stories flat regardless of slice' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)

    visit_map

    assert_page_includes('Register')
    refute_page_includes('slice-header')
  end

  it 'normal view preserves slice order' do
    slice_a = create_release_slice('Alpha')
    slice_b = create_release_slice('Beta')
    story_1 = create_story('In Beta', under_task: @task)
    story_2 = create_story('In Alpha', under_task: @task)
    create_story('Unsliced', under_task: @task)
    move_story_to_slice(story_1, release_slice_id: slice_b.id)
    move_story_to_slice(story_2, release_slice_id: slice_a.id)

    visit_map
    body = page_body
    pos_unsliced = body.index('Unsliced')
    pos_alpha    = body.index('In Alpha')
    pos_beta     = body.index('In Beta')

    assert_operator pos_unsliced, :<, pos_alpha, 'Unsliced should appear before Alpha slice stories'
    assert_operator pos_alpha, :<, pos_beta, 'Alpha slice stories should appear before Beta slice stories'
  end

  it 'slices view groups stories by slice' do
    slice = create_release_slice('MVP')
    sliced_story = create_story('Register', under_task: @task)
    create_story('Verify email', under_task: @task)
    move_story_to_slice(sliced_story, release_slice_id: slice.id)

    visit_map_slices

    assert_page_includes('Register')
    assert_page_includes('Verify email')
    assert_page_includes('MVP')
    assert_page_includes('slice-header')
  end

  it 'auto-increments slice position' do
    s1 = create_release_slice('MVP')
    s2 = create_release_slice('Beta')

    assert_operator s2.position, :>, s1.position
  end

  it 'rejects editing release slice from another map' do
    other_map = Map.create(team_id: @team.id, name: 'Other', position: 9000)
    foreign = ReleaseSlice.create(map_id: other_map.id, team_id: @team.id, name: 'Foreign', position: 1000)

    assert_raises(RuntimeError, '404 - Not Found') do
      driver.submit_edit_release_slice(@map, foreign, name: 'Hacked')
    end

    foreign.refresh

    assert_equal 'Foreign', foreign.name
  end

  it 'ignores move to a slice from another map' do
    create_release_slice('MVP')
    story = create_story('Register', under_task: @task)

    other_map = Map.create(team_id: @team.id, name: 'Other', position: 9000)
    foreign_slice = ReleaseSlice.create(map_id: other_map.id, team_id: @team.id, name: 'Foreign', position: 1000)

    move_story_to_slice(story, release_slice_id: foreign_slice.id)

    story.refresh

    assert_nil story.release_slice_id
  end

  it 'moves a story to another slice via reorder endpoint' do
    slice_a = create_release_slice('MVP')
    slice_b = create_release_slice('Beta')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice_a.id)

    reorder_stories(@task, story_ids: [story.id], release_slice_id: slice_b.id)

    story.refresh

    assert_equal slice_b.id, story.release_slice_id
    assert_event_recorded(entity: story, action: 'slice_changed')
  end

  it 'moves a story to unsliced via reorder endpoint' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)

    reorder_stories(@task, story_ids: [story.id], release_slice_id: '')

    story.refresh

    assert_nil story.release_slice_id
  end

  it 'moves planned story into a slice that already has a released story' do
    slice = create_release_slice('MVP')
    released = create_story('Released one', under_task: @task)
    assign_person(released, person: @alice)
    bob = add_person(name: 'Bob', email: 'bob@acme.co')
    assign_person(released, person: bob)
    deploy_story(released)
    release_story(released)
    released.update(release_slice_id: slice.id)

    planned = create_story('Planned one', under_task: @task)

    reorder_stories(@task, story_ids: [planned.id, released.id], release_slice_id: slice.id)

    planned.refresh

    assert_equal slice.id, planned.release_slice_id
    released.refresh

    assert_equal slice.id, released.release_slice_id
  end

  it 'reorder with release_slice_id for released story returns 422' do
    create_release_slice('MVP')
    slice_b = create_release_slice('Beta')
    story = create_story('Register', under_task: @task)
    assign_person(story, person: @alice)
    bob = add_person(name: 'Bob', email: 'bob@acme.co')
    assign_person(story, person: bob)
    deploy_story(story)
    release_story(story)

    resp = reorder_stories(@task, story_ids: [story.id], release_slice_id: slice_b.id)

    assert_equal 422, resp.status
    story.refresh

    assert_nil story.release_slice_id
  end

  it 'archived story does not appear in sliced view' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)
    archive_story(story)

    visit_map_slices

    refute_content_includes('Register')
  end
end

describe 'Release slices - History' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
  end

  it 'shows slice edit history with before and after' do
    slice = create_release_slice('MVP')
    submit_edit_release_slice(slice, name: 'Beta')

    visit_release_slices_index

    assert_page_includes('Alice')
    assert_page_includes('MVP')
    assert_page_includes('Beta')
  end

  it 'htmx edit returns updated history' do
    slice = create_release_slice('MVP')

    resp = driver.htmx_edit_release_slice(@map, slice, name: 'Beta')

    assert_includes resp.body, 'renamed'
    assert_includes resp.body, 'MVP'
    assert_includes resp.body, 'Beta'
  end

  it 'shows slice creation in history' do
    create_release_slice('MVP')

    visit_release_slices_index

    assert_page_includes('created')
  end

  it 'limits history to 20 most recent and shows Show all link' do
    slice = create_release_slice('MVP')

    25.times do |i|
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: slice, action: 'edited',
        before_state: { name: "v#{i}" }, after_state: { name: "v#{i + 1}" }
      )
    end

    visit_release_slices_index

    body = page_body

    assert_shown('history-show-all', body)
    assert_includes body, 'v25'
    refute_includes body, '&quot;v0&quot;'
  end

  it 'show-all returns full history' do
    slice = create_release_slice('MVP')

    25.times do |i|
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: slice, action: 'edited',
        before_state: { name: "v#{i}" }, after_state: { name: "v#{i + 1}" }
      )
    end

    driver.visit_release_slice_history(@map)

    body = page_body

    assert_includes body, 'v25'
    assert_includes body, '&quot;v0&quot;'
    refute_shown('history-show-all', body)
  end
end

describe 'Release slices - Delete' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
  end

  it 'deletes an empty slice' do
    slice = create_release_slice('MVP')

    driver.submit_delete_release_slice(@map, slice)

    assert_nil(BypassRLS.call { ReleaseSlice[slice.id] })
  end

  it 'shows deleted slice in history' do
    create_release_slice('MVP')
    slice2 = create_release_slice('Beta')
    driver.submit_delete_release_slice(@map, slice2)

    visit_release_slices_index

    body = page_body

    assert_includes body, 'MVP'
    assert_includes body, 'Beta'
  end

  it 'rejects htmx delete of a slice with stories' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)

    resp = driver.htmx_delete_release_slice(@map, slice)

    refute_nil ReleaseSlice[slice.id]
    assert_equal 422, resp.status
  end

  it 'rejects deleting a slice with stories' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)

    driver.submit_delete_release_slice(@map, slice)

    refute_nil ReleaseSlice[slice.id]
  end

  it 'rejects delete on a locked map' do
    slice = create_release_slice('MVP')
    lock_map

    driver.submit_delete_release_slice(@map, slice)

    refute_nil ReleaseSlice[slice.id]
  end

  it 'rejects htmx delete on a locked map' do
    slice = create_release_slice('MVP')
    lock_map

    resp = driver.htmx_delete_release_slice(@map, slice)

    refute_nil ReleaseSlice[slice.id]
    assert_equal 422, resp.status
  end

  it 'records a delete event' do
    slice = create_release_slice('MVP')

    driver.submit_delete_release_slice(@map, slice)

    assert_event_recorded(entity: slice, action: 'deleted')
  end

  it 'deletes a slice whose stories are all archived' do
    slice = create_release_slice('MVP')
    story = create_story('Register', under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)
    archive_story(story)

    driver.submit_delete_release_slice(@map, slice)

    assert_nil(BypassRLS.call { ReleaseSlice[slice.id] })
    story.refresh

    assert_nil story.release_slice_id
  end
end

describe 'Release slices - Edit' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @slice    = create_release_slice('MVP')
  end

  it 'shows slice names on index page' do
    visit_release_slices_index

    assert_page_includes('MVP')
  end

  it 'updates the name' do
    submit_edit_release_slice(@slice, name: 'Beta')

    @slice.reload

    assert_equal 'Beta', @slice.name

    event = assert_event_recorded(entity: @slice, action: 'edited')

    assert_equal 'MVP', event.before_state['name']
    assert_equal 'Beta', event.after_state['name']
  end

  it 'requires a name' do
    submit_edit_release_slice(@slice, name: '')

    @slice.reload

    assert_equal 'MVP', @slice.name
  end

  it 'rejects an edit name over 100 characters' do
    resp = driver.htmx_edit_release_slice(@map, @slice, name: 'x' * 101)

    @slice.reload

    assert_equal 'MVP', @slice.name
    assert_error_shown(resp.body)
  end
end
