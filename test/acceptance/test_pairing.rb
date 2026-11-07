# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Pairing states' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    @bob   = add_person(name: 'Bob',   email: 'bob@acme.co')
    @carol = add_person(name: 'Carol', email: 'carol@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @story    = create_story('Register', under_task: @task)
  end

  it 'one person assigned stays planned' do
    assign_person(@story, person: @alice)

    @story.refresh

    assert_equal 'planned', @story.status
  end

  it 'activates when second person is assigned (paired)' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    @story.refresh

    assert_equal 'active', @story.status
    assert_equal 2, StoryAssignment.where(story_id: @story.id).count
  end

  it 'shows paired label on map' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    visit_map

    assert_page_includes('paired')
  end

  it 'shows ensemble label for 3+ people and records collaboration_changed' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    assign_person(@story, person: @carol)

    visit_map

    assert_page_includes('ensemble')

    event = assert_event_recorded(entity: @story, action: 'collaboration_changed')
    assert_equal 'paired', event.before_state['mode']
    assert_equal 'ensemble', event.after_state['mode']
    assert_includes event.after_state['person_ids'], @alice.id
    assert_includes event.after_state['person_ids'], @bob.id
    assert_includes event.after_state['person_ids'], @carol.id
  end

  it 'unassign from paired (2→1) stays active as solo and records collaboration_changed' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    sa = StoryAssignment.where(story_id: @story.id, person_id: @bob.id).first
    unassign_person(@story, sa)

    @story.refresh

    assert_equal 'active', @story.status

    visit_map

    assert_page_includes('solo')

    event = assert_event_recorded(entity: @story, action: 'collaboration_changed')
    assert_equal 'paired', event.before_state['mode']
    assert_equal 'solo', event.after_state['mode']
    assert_equal @alice.id, event.after_state['solo_person_id']
    assert_equal [@alice.id], event.after_state['person_ids']
  end

  it 'unassign from solo (1→0) reverts to planned' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    # Now paired/active — remove bob, then alice
    sa_bob = StoryAssignment.where(story_id: @story.id, person_id: @bob.id).first
    unassign_person(@story, sa_bob)

    sa_alice = StoryAssignment.where(story_id: @story.id, person_id: @alice.id).first
    unassign_person(@story, sa_alice)

    @story.refresh

    assert_equal 'planned', @story.status
  end

  it 'unassign from ensemble (3→2) stays active as paired and records collaboration_changed' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    assign_person(@story, person: @carol)

    sa = StoryAssignment.where(story_id: @story.id, person_id: @carol.id).first
    unassign_person(@story, sa)

    @story.refresh

    assert_equal 'active', @story.status
    assert_equal 2, StoryAssignment.where(story_id: @story.id).count

    events = Event.where(entity_id: @story.id, action: 'collaboration_changed')
      .order(:event_no).all
    ensemble_to_paired = events.reverse_each.detect { |e| e.after_state['mode'] == 'paired' }

    refute_nil ensemble_to_paired
    assert_equal 'ensemble', ensemble_to_paired.before_state['mode']
  end

  it 're-pairing from solo (1→2) records collaboration_changed' do
    dan = add_person(name: 'Dan', email: 'dan@acme.co')
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    sa_bob = StoryAssignment.where(story_id: @story.id, person_id: @bob.id).first
    unassign_person(@story, sa_bob)

    assign_person(@story, person: dan)

    events = Event.where(entity_id: @story.id, action: 'collaboration_changed')
      .order(:event_no).all
    solo_to_paired = events.reverse_each.detect { |e|
      e.before_state['mode'] == 'solo' && e.after_state['mode'] == 'paired'
    }

    refute_nil solo_to_paired, 'Expected solo→paired collaboration_changed event'
    assert_includes solo_to_paired.after_state['person_ids'], @alice.id
    assert_includes solo_to_paired.after_state['person_ids'], dan.id
  end
end
