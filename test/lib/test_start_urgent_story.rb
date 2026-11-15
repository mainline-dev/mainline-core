# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/start_urgent_story'

describe StartUrgentStory do
  cover 'StartUrgentStory*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @bob = Person.create(name: 'Bob', email: 'bob@test.mainline')
    [@alice, @bob].each { |person| TeamMembership.create(team_id: @team.id, person_id: person.id) }
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Run the shop', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Operate', position: 1000)
    @patch = story('Rotate the key')
  end

  def story(title)
    Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: title,
      position: (Story.max(:position) || 0) + 1000, created_by_id: @alice.id)
  end

  def start(story = @patch, reason: 'The payment key leaked', person: @alice)
    StartUrgentStory.call(story: story, person_id: person.id, reason: reason, team: @team, actor_id: person.actor_id)
  end

  it 'starts the story with the person on it, recording why it is urgent' do
    result = start

    assert_predicate result, :success?
    assert_equal 'active', @patch.reload.status
    assert_equal [@alice.id], StoryAssignment.where(story_id: @patch.id).select_map(:person_id)
    assert_equal 'The payment key leaked', Event.where(entity_id: @patch.id, action: 'marked_urgent').first.after_state['reason']
  end

  it 'keeps the reason without the space around it' do
    start(reason: '  The payment key leaked  ')

    assert_equal 'The payment key leaked', Event.where(entity_id: @patch.id, action: 'marked_urgent').first.after_state['reason']
  end

  it 'refuses without a reason, and starts nothing' do
    result = start(reason: '   ')

    refute_predicate result, :success?
    assert_equal 'reason-needed', result.reason
    assert_equal 'planned', @patch.reload.status
    assert_empty Event.where(entity_id: @patch.id, action: 'marked_urgent').all
  end

  it 'refuses when no reason was sent at all' do
    assert_equal 'reason-needed', start(reason: nil).reason
  end

  it 'refuses a story that has already started' do
    @patch.update(status: 'active')

    assert_equal 'not-planned', start.reason
  end

  it 'refuses while the team has another urgent story' do
    start
    later = story('See failed payments')

    result = start(later, person: @bob)

    assert_equal 'urgent-taken', result.reason
    assert_equal 'planned', later.reload.status
  end

  it 'marks nothing urgent when the person cannot go on the story' do
    outsider = Person.create(name: 'Outsider', email: 'outsider@test.mainline')

    result = start(person: outsider)

    refute_predicate result, :success?
    assert_equal 'not-assigned', result.reason
    assert_equal 'Person is not a team member', result.error
    assert_empty Event.where(entity_id: @patch.id, action: 'marked_urgent').all
  end

  it 'says what each refusal means' do
    assert_equal 'reason-needed', start(reason: '').reason
    refute_empty start(reason: '').error
  end
end
