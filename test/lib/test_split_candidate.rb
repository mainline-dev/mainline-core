# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/split_candidate'
require 'timecop'

describe SplitCandidate do
  cover 'SplitCandidate*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @bob   = Person.create(name: 'Bob',   email: 'bob@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @alice.id)
    TeamMembership.create(team_id: @team.id, person_id: @bob.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: @activity.id, persona_id: @persona.id, team_id: @team.id)
    @task = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Search', position: 1000
    )
    @seq = 0
  end

  after do
    Timecop.return
  end

  def create_story(title)
    @seq += 1
    pos = @seq * 1000
    Story.create(
      task_id: @task.id, map_id: @map.id, team_id: @team.id,
      title: title, position: pos, created_by_id: @alice.id
    )
  end

  def activate_and_release(story, cycle_hours:)
    story.update(status: 'active')
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'activated',
      after_state: { reason: 'paired', assignment_count: 2 }
    )
    Timecop.travel(Time.now + (cycle_hours * 3600))
    story.update(status: 'released', released_at: Time.now)
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'released',
      after_state: { status: 'released' }
    )
  end

  def build_baseline(count: 10, cycle_hours: 48)
    count.times do |i|
      s = create_story("Baseline #{i}")
      activate_and_release(s, cycle_hours: cycle_hours)
    end
  end

  describe '.check' do
    it 'returns false for planned story' do
      story = create_story('Planned')

      refute SplitCandidate.check(story, team_id: @team.id)
    end

    it 'returns false for active story without baseline' do
      story = create_story('Active')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )

      refute SplitCandidate.check(story, team_id: @team.id)
    end

    it 'returns true when story exceeds percentile threshold' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      story = create_story('Long runner')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )
      Timecop.travel(Time.now + (72 * 3600))

      assert SplitCandidate.check(story, team_id: @team.id)
    end

    it 'returns false when story is within threshold' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      story = create_story('Quick one')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )
      Timecop.travel(Time.now + (24 * 3600))

      refute SplitCandidate.check(story, team_id: @team.id)
    end

    it 'uses pre-computed threshold when passed' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))

      story = create_story('Pre-computed')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )
      Timecop.travel(Time.now + (72 * 3600))

      assert SplitCandidate.check(story, team_id: @team.id, threshold: 48 * 3600)
      refute SplitCandidate.check(story, team_id: @team.id, threshold: 100 * 3600)
    end
  end

  describe '.check_batch' do
    it 'returns empty hash for no stories' do
      result = SplitCandidate.check_batch([], team_id: @team.id)

      assert_equal({}, result)
    end

    it 'returns false for planned stories' do
      planned = create_story('Planned')

      result = SplitCandidate.check_batch([planned], team_id: @team.id)

      assert_equal({}, result)
    end

    it 'returns false for active stories without baseline' do
      story = create_story('Active')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )

      result = SplitCandidate.check_batch([story], team_id: @team.id)

      assert_equal({ story.id => false }, result)
    end

    it 'flags stories exceeding threshold' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      story = create_story('Long runner')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )
      Timecop.travel(Time.now + (72 * 3600))

      result = SplitCandidate.check_batch([story], team_id: @team.id)

      assert result[story.id]
    end

    it 'does not flag stories within threshold' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      story = create_story('Quick')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )
      Timecop.travel(Time.now + (24 * 3600))

      result = SplitCandidate.check_batch([story], team_id: @team.id)

      refute result[story.id]
    end

    it 'returns false for active story never activated' do
      story = create_story('No event')
      story.update(status: 'active')

      result = SplitCandidate.check_batch([story], team_id: @team.id, threshold: 100)

      refute result[story.id]
    end

    it 'handles mix of active and planned stories' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      planned = create_story('Planned')
      active = create_story('Active')
      active.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: active,
        action: 'activated',
        after_state: { reason: 'paired' }
      )
      Timecop.travel(Time.now + (72 * 3600))

      result = SplitCandidate.check_batch([planned, active], team_id: @team.id)

      refute_includes result, planned.id
      assert result[active.id]
    end

    it 'uses pre-computed threshold when passed' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Test')
      story.update(status: 'active')
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'activated',
        after_state: { reason: 'paired' }
      )
      Timecop.travel(Time.now + (72 * 3600))

      result = SplitCandidate.check_batch([story], team_id: @team.id, threshold: 48 * 3600)

      assert result[story.id]
    end
  end

  describe '.percentile_threshold' do
    it 'returns nil with fewer than minimum released stories' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 5, cycle_hours: 48)

      assert_nil SplitCandidate.percentile_threshold(@team.id)
    end

    it 'returns threshold at 80th percentile by default' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      threshold = SplitCandidate.percentile_threshold(@team.id)

      refute_nil threshold
      assert_in_delta 48 * 3600, threshold, 3600
    end

    it 'returns nil when percentile is 100' do
      TeamConstraint.create(
        team_id: @team.id, constraint_key: 'split_percentile',
        value: 100, min_value: 0, max_value: 100, default_value: 80
      )
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      assert_nil SplitCandidate.percentile_threshold(@team.id)
    end

    it 'respects custom min_released constraint' do
      TeamConstraint.create(
        team_id: @team.id, constraint_key: 'split_min_released',
        value: 3, min_value: 1, max_value: 100, default_value: 10
      )
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 3, cycle_hours: 48)

      refute_nil SplitCandidate.percentile_threshold(@team.id)
    end

    it 'caches computed threshold on the team' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      build_baseline(count: 10, cycle_hours: 48)

      SplitCandidate.percentile_threshold(@team.id)
      @team.refresh

      refute_nil @team.split_threshold_seconds
      assert_in_delta 48 * 3600, @team.split_threshold_seconds, 3600
    end

    it 'returns cached value without recomputing' do
      @team.update(split_threshold_seconds: 99_999.0)

      threshold = SplitCandidate.percentile_threshold(@team.id)

      assert_in_delta 99_999.0, threshold
    end
  end

  describe '.invalidate_threshold!' do
    it 'clears the cached threshold' do
      @team.update(split_threshold_seconds: 99_999.0)

      SplitCandidate.invalidate_threshold!(@team.id)
      @team.refresh

      assert_nil @team.split_threshold_seconds
    end
  end
end
