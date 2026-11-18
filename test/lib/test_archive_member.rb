# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/archive_member'

describe ArchiveMember do
  cover 'ArchiveMember*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice, @bob, @carol = %w[Alice Bob Carol].map { |name| member(name) }
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @paired = story('Guest checkout', 1000, @alice, @bob)
    @alone = story('Pay by card', 2000, @bob)
    @carols = story('Refund an order', 3000, @carol)
    @now = Time.utc(2030, 1, 7, 9)
  end

  def member(name)
    Person.create(name: name, email: "#{name.downcase}@test.mainline").tap { |person|
      TeamMembership.create(team_id: @team.id, person_id: person.id, working: true)
    }
  end

  # An active story with these people on it.
  def story(title, position, *people)
    story = Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: title, position: position,
      created_by_id: @alice.id)
    story.update(status: 'active')
    people.each { |person| StoryAssignment.create(story_id: story.id, person_id: person.id, team_id: @team.id) }
    story
  end

  def membership(person)
    TeamMembership.first(team_id: @team.id, person_id: person.id)
  end

  def archive_bob
    ArchiveMember.call(membership: membership(@bob), actor: @alice.actor, now: @now)
  end

  def on(story)
    StoryAssignment.where(story_id: story.id).select_map(:person_id)
  end

  def recorded(entity, action)
    Event.where(entity_id: entity.id, action: action).order(:event_no).all
  end

  it 'marks the member as having left from now, and records it with their name, leaving the others' do
    archive_bob
    by = recorded(membership(@bob), 'member_archived').map { |event| [event.actor_id, event.before_state] }
    left = [@bob, @alice, @carol].map { |person| membership(person).left_at }

    assert_equal [@now, nil, nil], left
    assert_equal [[@alice.actor.id, { 'person_id' => @bob.id, 'name' => 'Bob' }]], by
  end

  it "takes them off every story they were on, recording each, and leaves everyone else's stories alone" do
    archive_bob
    unassigned = [@paired, @alone, @carols].map { |story| recorded(story, 'person_unassigned').map(&:before_state) }

    assert_equal [[@alice.id], [], [@carol.id]], [on(@paired), on(@alone), on(@carols)]
    assert_equal [[{ 'person_id' => @bob.id }], [{ 'person_id' => @bob.id }], []], unassigned
  end

  it 'puts a story left with nobody back to planned, and records a pair left with one person as that person alone' do
    archive_bob
    now_alone = recorded(@paired, 'collaboration_changed').map { |event| event.after_state.values_at('mode', 'solo_person_id') }
    statuses = [@paired, @alone, @carols].map { |story| story.refresh.status }

    assert_equal %w[active planned active], statuses
    assert_equal [['solo', @alice.id]], now_alone
    assert_equal [{ 'reason' => 'no_assignees' }], recorded(@alone, 'deactivated').map(&:after_state)
  end
end
