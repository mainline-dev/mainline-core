# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/unassign_person'

describe UnassignPerson do
  cover 'UnassignPerson*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice, @bob = %w[Alice Bob].map { |name|
      Person.create(name: name, email: "#{name.downcase}@test.mainline").tap { |person|
        TeamMembership.create(team_id: @team.id, person_id: person.id, working: true)
      }
    }
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = story('Guest checkout', 1000, @alice, @bob)
    @other = story('Pay by card', 2000, @alice)
  end

  # An active story with these people on it.
  def story(title, position, *people)
    story = Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: title, position: position,
      created_by_id: @alice.id)
    story.update(status: 'active')
    people.each { |person| StoryAssignment.create(story_id: story.id, person_id: person.id, team_id: @team.id) }
    story
  end

  def unassign(person, story = @story)
    UnassignPerson.call(story: story.refresh, assignment: StoryAssignment.first(story_id: story.id, person_id: person.id),
      actor: @alice.actor)
  end

  def on(story)
    StoryAssignment.where(story_id: story.id).select_map(:person_id)
  end

  def recorded(story, action)
    Event.where(entity_id: story.id, action: action).order(:event_no).all
  end

  it 'takes a person off the story and records it, and that the pair is now one person working alone' do
    result = unassign(@bob)
    changed = recorded(@story, 'collaboration_changed')
    now_working = changed.map { |event| event.after_state.values_at('mode', 'solo_person_id') }

    assert_equal [true, nil], [result.success?, result.error]
    assert_equal [[@alice.id], [@alice.id]], [on(@story), on(@other)]
    assert_equal [{ 'person_id' => @bob.id }], recorded(@story, 'person_unassigned').map(&:before_state)
    assert_equal [{ 'mode' => 'paired', 'assignment_count' => 2 }], changed.map(&:before_state)
    assert_equal [['solo', @alice.id]], now_working
    assert_equal 'active', @story.refresh.status
  end

  it 'puts an active story back to planned once its last person leaves' do
    unassign(@bob)
    unassign(@alice)

    assert_equal ['planned', []], [@story.refresh.status, on(@story)]
    assert_equal [{ 'reason' => 'no_assignees' }], recorded(@story, 'deactivated').map(&:after_state)
    assert_equal 1, recorded(@story, 'collaboration_changed').size
  end

  it 'takes the last person off a planned story, leaving it planned' do
    @other.update(status: 'planned')

    unassign(@alice, @other)

    assert_equal ['planned', []], [@other.refresh.status, on(@other)]
    assert_empty recorded(@other, 'deactivated')
    assert_empty recorded(@other, 'collaboration_changed')
  end

  it 'refuses on a released story, saying why, and changes nothing' do
    StoryAssignment.where(story_id: @story.id).delete
    @story.update(status: 'released', released_at: Time.now)
    StoryAssignment.create(story_id: @story.id, person_id: @bob.id, team_id: @team.id)

    result = unassign(@bob)

    assert_equal [false, [@bob.id]], [result.success?, on(@story)]
    refute_nil result.error
    assert_empty recorded(@story, 'person_unassigned')
  end
end
