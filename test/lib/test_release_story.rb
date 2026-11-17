# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_scenario'
require_relative '../../lib/release_story'

describe ReleaseStory do
  cover 'ReleaseStory*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice = member('Alice')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = deployed_story
    @now = Time.utc(2030, 1, 7, 9)
  end

  def member(name)
    Person.create(name: name, email: "#{name.downcase}@test.mainline").tap { |person|
      TeamMembership.create(team_id: @team.id, person_id: person.id, working: true)
    }
  end

  # An active story deployed once, with Alice on it and its one scenario done.
  def deployed_story
    story = Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: 'Guest checkout',
      position: 1000, created_by_id: @alice.id)
    story.update(status: 'active', deploy_count: 1, first_deployed_at: Time.now, last_deployed_at: Time.now)
    StoryAssignment.create(story_id: story.id, person_id: @alice.id, team_id: @team.id)
    AddScenario.call(story: story, actor: @alice.actor, name: 'Pays', given_text: 'a basket', when_text: 'they pay',
      then_text: 'it is paid')
    Scenario.where(story_id: story.id).update(done_at: Time.now)
    story
  end

  # Another story Alice is on, with a scenario not done.
  def other_story
    story = Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: 'Pay by card',
      position: 2000, created_by_id: @alice.id)
    story.update(status: 'active')
    StoryAssignment.create(story_id: story.id, person_id: @alice.id, team_id: @team.id)
    AddScenario.call(story: story, actor: @alice.actor, name: 'Card', given_text: 'a card', when_text: 'they pay',
      then_text: 'the card is charged')
    story
  end

  def release(reason: nil)
    ReleaseStory.call(story: @story.refresh, team: @team, actor: @alice.actor, reason: reason, now: @now)
  end

  def recorded(action)
    Event.where(entity_id: @story.id, action: action).order(:event_no).all
  end

  it 'releases a deployed story, unassigning everyone on it, recording the release and clearing the split threshold' do
    @team.update(split_threshold_seconds: 3600)
    other = other_story

    result = release

    assert_predicate result, :success?
    assert_equal ['released', @now], @story.refresh.values.values_at(:status, :released_at)
    assert_empty StoryAssignment.where(story_id: @story.id).all
    assert_equal [{ 'person_id' => @alice.id, 'reason' => 'released' }], recorded('person_unassigned').map(&:before_state)
    assert_equal [{ 'status' => 'released' }], recorded('released').map(&:after_state)
    assert_nil @team.refresh.split_threshold_seconds
    assert_equal 1, StoryAssignment.where(story_id: other.id).count
  end

  it 'lets a story with no scenarios go with a reason, and records that it did and why' do
    Scenario.where(story_id: @story.id).delete

    assert_predicate release(reason: 'A typo in the footer'), :success?
    assert_equal [{ 'status' => 'released', 'without_scenarios' => true, 'reason' => 'A typo in the footer' }],
      recorded('released').map(&:after_state)
  end

  it 'refuses a story that is not active, or not yet deployed, saying why, and changes nothing' do
    @story.update(status: 'planned')
    not_active = release
    @story.update(status: 'active', deploy_count: 0, first_deployed_at: nil, last_deployed_at: nil)
    not_deployed = release

    assert_equal [false, false], [not_active.success?, not_deployed.success?]
    assert(not_active.error && not_deployed.error)
    refute_equal not_active.error, not_deployed.error
    assert_equal 'active', @story.refresh.status
    assert_equal 1, StoryAssignment.where(story_id: @story.id).count
    assert_empty recorded('released')
  end

  it 'holds back a story with scenarios not done, counting them, and one with no scenarios unless someone says why' do
    AddScenario.call(story: @story, actor: @alice.actor, name: 'Refunds', given_text: 'a payment', when_text: 'they refund',
      then_text: 'it is refunded')
    other_story
    unverified = release
    Scenario.where(story_id: @story.id).delete
    no_scenarios = release

    assert_equal [false, ReleaseBlock::UNVERIFIED, 1], [unverified.success?, unverified.reason, unverified.error[/\A\d+/].to_i]
    assert_equal [ReleaseBlock::NO_SCENARIOS, ReleaseBlock::REFUSALS.fetch(ReleaseBlock::NO_SCENARIOS)],
      [no_scenarios.reason, no_scenarios.error]
    assert_equal ReleaseBlock::REASON_NEEDED, release(reason: '  ').reason
    assert_empty recorded('released')
  end

  describe 'on a team of two' do
    before { @bob = member('Bob') }

    it 'holds back a story one person worked on until it is walked through' do
      result = release

      assert_equal [false, TwoPersonRule::REFUSAL, TwoPersonRule::REASON], [result.success?, result.error, result.reason]
      assert_empty recorded('released')
    end

    it 'lets an urgent story go before its walkthrough, and records that it did' do
      RecordEvent.call(actor_id: @alice.actor.id, entity: @story, action: UrgentStory::ACTION)

      assert_predicate release, :success?
      assert(recorded('released').last.after_state[TwoPersonRule::BEFORE_WALKTHROUGH])
    end

    it 'releases a story two people worked on, saying nothing of a walkthrough' do
      RecordEvent.call(actor_id: @alice.actor.id, entity: @story, action: 'collaboration_changed',
        after_state: { mode: 'paired' })

      assert_predicate release, :success?
      refute recorded('released').last.after_state.key?(TwoPersonRule::BEFORE_WALKTHROUGH)
    end
  end
end
