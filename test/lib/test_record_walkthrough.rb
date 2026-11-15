# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/record_walkthrough'

describe RecordWalkthrough do
  cover 'RecordWalkthrough*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice, @bob, @carol = %w[Alice Bob Carol].map { |name|
      Person.create(name: name, email: "#{name.downcase}@test.mainline").tap { |person|
        TeamMembership.create(team_id: @team.id, person_id: person.id)
      }
    }
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
    @story = create_story('Find things', on_it: @alice)
  end

  # An active story one person is on, deployed once.
  def create_story(title, on_it:)
    position = (Story.where(task_id: @task.id).max(:position) || 0) + 1000
    story = Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: title, position: position,
      created_by_id: @alice.id, status: 'active', deploy_count: 1, first_deployed_at: Time.now,
      last_deployed_at: Time.now)
    StoryAssignment.create(story_id: story.id, person_id: on_it.id, team_id: @team.id)
    story
  end

  def walkthroughs
    Event.where(entity_id: @story.id, action: 'walked_through').order(:event_no).all
  end

  def record(attendees, by: @alice)
    RecordWalkthrough.call(story: @story, actor: by.actor, attendee_ids: attendees.map(&:id))
  end

  it 'records who attended, on the story, in the name of whoever wrote it down' do
    result = record([@bob, @carol], by: @carol)

    assert_predicate result, :success?
    assert_equal 1, walkthroughs.length
    assert_equal [@bob.id, @carol.id], walkthroughs.first.after_state['attendee_ids']
    assert_equal @carol.actor.id, walkthroughs.first.actor_id
    assert_equal @team.id, walkthroughs.first.team_id
  end

  it 'records how many times the story had been deployed by then' do
    @story.update(deploy_count: 3)

    record([@bob])

    assert_equal 3, walkthroughs.first.after_state['deploy_count']
  end

  it 'records each walkthrough of a story walked through more than once' do
    record([@bob])
    record([@carol])

    assert_equal([[@bob.id], [@carol.id]], walkthroughs.map { |event| event.after_state['attendee_ids'] })
  end

  it 'records nothing for a story that has not been deployed' do
    @story.update(deploy_count: 0, first_deployed_at: nil, last_deployed_at: nil)

    result = record([@bob])

    refute_predicate result, :success?
    assert_equal 'not-deployed', result.reason
    refute_nil result.error
    assert_empty walkthroughs
  end

  it 'records nothing when someone attending is on the story, and says who' do
    result = record([@bob, @alice])

    refute_predicate result, :success?
    assert_equal 'attendee-on-story', result.reason
    assert_includes result.error, 'Alice'
    assert_empty walkthroughs
  end

  it 'takes someone who is on another story as attending' do
    create_story('Pay', on_it: @bob)

    assert_predicate record([@bob]), :success?
  end
end
