# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/lead_time'
require 'timecop'

describe LeadTime do
  cover 'LeadTime*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @alice.id)
    @bob = Person.create(name: 'Bob', email: 'bob@test.mainline')
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
    Story.create(
      task_id: @task.id, map_id: @map.id, team_id: @team.id,
      title: title, position: @seq * 1000, created_by_id: @alice.id
    )
  end

  def record(story, action, state = {})
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: action, after_state: state
    )
  end

  describe '.call' do
    it 'returns empty result for team with no released stories' do
      result = LeadTime.call(team_id: @team.id, days: nil)

      assert_empty result.buckets
    end

    it 'computes lead time for one released story' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Work')
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 12, 12, 0, 0))
      record(story, 'released', { status: 'released' })

      result = LeadTime.call(team_id: @team.id, days: nil)

      bucket = result.buckets.find { |b| b[:count].positive? }

      refute_nil bucket
      assert_equal 1, bucket[:count]
      assert_equal 2, result.max_lead_time
    end

    it 'groups stories with same lead time in one bucket' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s1 = create_story('First')
      record(s1, 'activated', { reason: 'paired' })
      s2 = create_story('Second')
      record(s2, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 12, 12, 0, 0))
      record(s1, 'released', { status: 'released' })
      record(s2, 'released', { status: 'released' })

      result = LeadTime.call(team_id: @team.id, days: nil)

      bucket = result.buckets.find { |b| b[:count].positive? }

      assert_equal 2, bucket[:count]
    end

    it 'distributes stories across buckets by lead time' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s1 = create_story('Fast')
      record(s1, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 11, 12, 0, 0))
      record(s1, 'released', { status: 'released' })

      s2 = create_story('Slow')
      record(s2, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 15, 12, 0, 0))
      record(s2, 'released', { status: 'released' })

      result = LeadTime.call(team_id: @team.id, days: nil)

      total = result.buckets.sum { |b| b[:count] }

      assert_equal 2, total
      assert_equal 4, result.max_lead_time
    end

    it 'filters by date range' do
      Timecop.freeze(Time.utc(2026, 2, 1, 12, 0, 0))
      old = create_story('Old')
      record(old, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 2, 3, 12, 0, 0))
      record(old, 'released', { status: 'released' })

      Timecop.freeze(Time.utc(2026, 3, 20, 12, 0, 0))
      recent = create_story('Recent')
      record(recent, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 22, 12, 0, 0))
      record(recent, 'released', { status: 'released' })

      Timecop.freeze(Time.utc(2026, 3, 25, 12, 0, 0))
      result = LeadTime.call(team_id: @team.id, days: 10)

      total = result.buckets.sum { |b| b[:count] }

      assert_equal 1, total
    end

    it 'uses 1-day buckets when max lead time <= 14' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Short')
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 13, 12, 0, 0))
      record(story, 'released', { status: 'released' })

      result = LeadTime.call(team_id: @team.id, days: nil)

      assert_equal 1, result.bucket_size
    end

    it 'uses 2-day buckets when max lead time is 15-30' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Medium')
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 21, 12, 0, 0))
      record(story, 'released', { status: 'released' })

      result = LeadTime.call(team_id: @team.id, days: nil)

      assert_equal 2, result.bucket_size
    end

    it 'uses 7-day buckets when max lead time > 30' do
      Timecop.freeze(Time.utc(2026, 2, 1, 12, 0, 0))
      story = create_story('Long')
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 15, 12, 0, 0))
      record(story, 'released', { status: 'released' })

      result = LeadTime.call(team_id: @team.id, days: nil)

      assert_equal 7, result.bucket_size
    end

    it 'excludes stories that were never activated' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Skipped')
      record(story, 'created', { title: 'Skipped' })

      Timecop.freeze(Time.utc(2026, 3, 12, 12, 0, 0))
      record(story, 'released', { status: 'released' })

      result = LeadTime.call(team_id: @team.id, days: nil)

      assert_empty result.buckets
    end

    it 'defaults to 30 days window' do
      Timecop.freeze(Time.utc(2026, 2, 1, 12, 0, 0))
      old = create_story('Old')
      record(old, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 2, 3, 12, 0, 0))
      record(old, 'released', { status: 'released' })

      Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))
      result = LeadTime.call(team_id: @team.id)

      assert_empty result.buckets
    end

    it 'skips rows with nil dates' do
      fake_rows = [{ released_on: Date.new(2026, 3, 12), activated_on: Date.new(2026, 3, 10) },
                   { released_on: nil, activated_on: Date.new(2026, 3, 10) }]
      LeadTime.stub(:raw_rows, fake_rows) do
        result = LeadTime.call(team_id: @team.id, days: nil)

        assert_equal(1, result.buckets.sum { |b| b[:count] })
      end
    end

    it 'computes p50 and p90 percentiles' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      stories = (1..10).map { |i| create_story("Story #{i}") }
      stories.each { |s| record(s, 'activated', { reason: 'paired' }) }

      stories.each_with_index do |s, i|
        Timecop.freeze(Time.utc(2026, 3, 1 + i + 1, 12, 0, 0))
        record(s, 'released', { status: 'released' })
      end

      Timecop.freeze(Time.utc(2026, 3, 20, 12, 0, 0))
      result = LeadTime.call(team_id: @team.id, days: nil)

      assert_equal 5, result.p50
      assert_equal 9, result.p90
    end

    it 'returns nil p50 and p90 when no data' do
      result = LeadTime.call(team_id: @team.id, days: nil)

      assert_nil result.p50
      assert_nil result.p90
    end

    it 'filters by map_id when provided' do
      map_b = Map.create(team_id: @team.id, name: 'Other', position: 2000)
      activity_b = Activity.create(map_id: map_b.id, team_id: @team.id, name: 'Other', position: 1000)
      task_b = Task.create(
        activity_id: activity_b.id, map_id: map_b.id, team_id: @team.id,
        name: 'Other task', position: 1000
      )

      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s1 = create_story('Map A story')
      record(s1, 'activated', { reason: 'paired' })

      s2 = Story.create(
        task_id: task_b.id, map_id: map_b.id, team_id: @team.id,
        title: 'Map B story', position: 1000, created_by_id: @alice.id
      )
      record(s2, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 12, 12, 0, 0))
      record(s1, 'released', { status: 'released' })
      record(s2, 'released', { status: 'released' })

      result_a = LeadTime.call(team_id: @team.id, days: nil, map_id: @map.id)
      result_b = LeadTime.call(team_id: @team.id, days: nil, map_id: map_b.id)
      result_all = LeadTime.call(team_id: @team.id, days: nil)

      assert_equal(1, result_a.buckets.sum { |b| b[:count] })
      assert_equal(1, result_b.buckets.sum { |b| b[:count] })
      assert_equal(2, result_all.buckets.sum { |b| b[:count] })
    end
  end
end
