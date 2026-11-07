# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Assignments' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    @bob   = add_person(name: 'Bob',   email: 'bob@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @story    = create_story('As a customer I can register', under_task: @task)
  end

  it 'assigns a person to a story' do
    assign_person(@story, person: @alice)

    assignment = StoryAssignment.where(story_id: @story.id, person_id: @alice.id).first

    refute_nil assignment, 'Assignment was not created'
    assert_event_recorded(entity: @story, action: 'person_assigned')
  end

  it 'shows assigned people on the map' do
    StoryAssignment.create(story_id: @story.id, person_id: @alice.id, team_id: @team.id)

    visit_map

    assert_page_includes('Alice')
  end

  it 'unassigns a person from a story' do
    assignment = StoryAssignment.create(story_id: @story.id, person_id: @alice.id, team_id: @team.id)

    unassign_person(@story, assignment)

    assert_nil StoryAssignment.where(story_id: @story.id, person_id: @alice.id).first
    assert_event_recorded(entity: @story, action: 'person_unassigned')
  end

  it 'rejects duplicate assignment' do
    StoryAssignment.create(story_id: @story.id, person_id: @alice.id, team_id: @team.id)

    assign_person(@story, person: @alice)

    assert_equal 1, StoryAssignment.where(story_id: @story.id, person_id: @alice.id).count
    assert_error_shown
  end

  it 'shows busy people as disabled in assign dropdown' do
    other_story = create_story('Other story', under_task: @task)
    StoryAssignment.create(story_id: other_story.id, person_id: @alice.id, team_id: @team.id)

    visit_assign_page(@story)

    body = page_body

    assert_includes body, %(disabled)
    assert_shown('busy-person', body)
  end

  it 'offers a person who is on a story but under the raised WIP limit' do
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'max_active_stories', value: 2,
      min_value: 1, max_value: 5, default_value: 1
    )
    other_story = create_story('Other story', under_task: @task)
    StoryAssignment.create(story_id: other_story.id, person_id: @alice.id, team_id: @team.id)

    visit_assign_page(@story)

    refute_shown('busy-person', page_body)

    assign_person(@story, person: @alice)

    refute_nil StoryAssignment.where(story_id: @story.id, person_id: @alice.id).first
  end

  it 'rejects if person already on another active story' do
    other_story = create_story('Other story', under_task: @task)
    StoryAssignment.create(story_id: other_story.id, person_id: @alice.id, team_id: @team.id)

    assign_person(@story, person: @alice)

    assert_nil StoryAssignment.where(story_id: @story.id, person_id: @alice.id).first
    assert_error_shown
  end

  it 'rejects assigning to a released story' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)

    carol = add_person(name: 'Carol', email: 'carol@acme.co')
    assign_person(@story, person: carol)

    assert_nil StoryAssignment.where(story_id: @story.id, person_id: carol.id).first

    assert_predicate driver, :redirected?
  end

  it 'rejects assigning a non-team member' do
    outsider = Person.create(name: 'Outsider', email: 'outsider@acme.co')

    assign_person(@story, person: outsider)

    assert_nil StoryAssignment.where(story_id: @story.id, person_id: outsider.id).first
    assert_error_shown
  end

  it 'rejects assigning an archived team member' do
    TeamMembership.where(team_id: @team.id, person_id: @bob.id).update(left_at: Time.now)

    assign_person(@story, person: @bob)

    assert_nil StoryAssignment.where(story_id: @story.id, person_id: @bob.id).first
    assert_error_shown
  end

  it 'excludes archived members from assign dropdown' do
    TeamMembership.where(team_id: @team.id, person_id: @bob.id).update(left_at: Time.now)

    visit_inline_assign(@story)

    body = page_body

    assert_includes body, 'Alice'
    refute_includes body, 'Bob'
  end

  it 'rejects assigning without selecting a person' do
    driver.submit_assign_person(@map, @story, person_id: '')

    assert_equal 0, StoryAssignment.where(story_id: @story.id).count
    assert_error_shown
  end

  it 'assigning a second person activates a planned story' do
    assign_person(@story, person: @alice)

    @story.reload

    assert_equal 'planned', @story.status

    assign_person(@story, person: @bob)

    @story.reload

    assert_equal 'active', @story.status
    assert_event_recorded(entity: @story, action: 'activated')
  end

  it 'single assignment activates when solo activation is enabled' do
    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'allow_solo_activation',
      value: 1, min_value: 0, max_value: 1, default_value: 0
    )

    assign_person(@story, person: @alice)

    @story.reload

    assert_equal 'active', @story.status
    assert_event_recorded(entity: @story, action: 'activated')
  end

  it 'single assignment does not activate when solo activation is off' do
    assign_person(@story, person: @alice)

    @story.reload

    assert_equal 'planned', @story.status
  end

  it 'returns inline assign dropdown with available people via HTMX' do
    add_person(name: 'Carol', email: 'carol@acme.co')
    StoryAssignment.create(story_id: @story.id, person_id: @alice.id, team_id: @team.id)

    visit_inline_assign(@story)

    body = page_body

    refute_includes body, 'Alice'
    assert_includes body, 'Bob'
    assert_includes body, 'Carol'
    assert_includes body, 'data-test-id="inline-assign-dropdown"'
  end

  it 'marks busy people as disabled in the inline assign dropdown' do
    other_story = create_story('Other story', under_task: @task)
    StoryAssignment.create(story_id: other_story.id, person_id: @alice.id, team_id: @team.id)

    visit_inline_assign(@story)

    body = page_body

    assert_includes body, 'disabled'
    assert_shown('busy-person', body)
    assert_includes body, 'Bob'
  end

  it 'returns empty state when no people are available for inline assign' do
    StoryAssignment.create(story_id: @story.id, person_id: @alice.id, team_id: @team.id)
    StoryAssignment.create(story_id: @story.id, person_id: @bob.id, team_id: @team.id)

    visit_inline_assign(@story)

    body = page_body

    assert_shown('inline-assign-empty', body)
  end

  it 'inline assign posts via HTMX and refreshes the grid' do
    driver.htmx_submit_inline_assign(@map, @story, person_id: @alice.id)

    assignment = StoryAssignment.where(story_id: @story.id, person_id: @alice.id).first

    refute_nil assignment, 'Assignment was not created'
    assert_event_recorded(entity: @story, action: 'person_assigned')
  end

  it 'unassigning the last person deactivates an active story' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)

    @story.reload

    assert_equal 'active', @story.status

    sa_alice = StoryAssignment.where(story_id: @story.id, person_id: @alice.id).first
    sa_bob   = StoryAssignment.where(story_id: @story.id, person_id: @bob.id).first

    unassign_person(@story, sa_alice)
    unassign_person(@story, sa_bob)

    @story.reload

    assert_equal 'planned', @story.status
    assert_event_recorded(entity: @story, action: 'deactivated')
  end
end
