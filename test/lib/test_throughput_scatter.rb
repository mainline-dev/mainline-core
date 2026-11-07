# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/throughput_scatter'
require 'timecop'

describe ThroughputScatter do
  cover 'ThroughputScatter*'
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
    it 'returns empty result for team with no events' do
      result = ThroughputScatter.call(team_id: @team.id, days: nil)

      assert_empty result.daily_counts
    end

    it 'counts one release as 1 on that date' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Ship')
      record(story, 'released', { status: 'released' })

      result = ThroughputScatter.call(team_id: @team.id, days: nil)

      assert_equal 1, result.daily_counts[Date.new(2026, 3, 10)]
    end

    it 'counts two releases on the same day as 2' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s1 = create_story('First')
      record(s1, 'released', { status: 'released' })
      s2 = create_story('Second')
      record(s2, 'released', { status: 'released' })

      result = ThroughputScatter.call(team_id: @team.id, days: nil)

      assert_equal 2, result.daily_counts[Date.new(2026, 3, 10)]
    end

    it 'tracks multiple days independently' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s1 = create_story('Day1')
      record(s1, 'released', { status: 'released' })

      Timecop.freeze(Time.utc(2026, 3, 12, 12, 0, 0))
      s2 = create_story('Day2a')
      record(s2, 'released', { status: 'released' })
      s3 = create_story('Day2b')
      record(s3, 'released', { status: 'released' })

      result = ThroughputScatter.call(team_id: @team.id, days: nil)

      assert_equal 1, result.daily_counts[Date.new(2026, 3, 10)]
      assert_equal 2, result.daily_counts[Date.new(2026, 3, 12)]
      assert_nil result.daily_counts[Date.new(2026, 3, 11)]
    end

    it 'filters by date range' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      old = create_story('Old')
      record(old, 'released', { status: 'released' })

      Timecop.freeze(Time.utc(2026, 3, 20, 12, 0, 0))
      recent = create_story('Recent')
      record(recent, 'released', { status: 'released' })

      Timecop.freeze(Time.utc(2026, 3, 25, 12, 0, 0))
      result = ThroughputScatter.call(team_id: @team.id, days: 10)

      assert_equal Date.new(2026, 3, 15), result.start_date
      assert_equal Date.new(2026, 3, 25), result.end_date
      assert_nil result.daily_counts[Date.new(2026, 3, 1)]
      assert_equal 1, result.daily_counts[Date.new(2026, 3, 20)]
    end

    it 'counts deploy events when action is deployed' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Deploy')
      record(story, 'deployed', { deploy_count: 1 })

      result = ThroughputScatter.call(team_id: @team.id, action: 'deployed', days: nil)

      assert_equal 1, result.daily_counts[Date.new(2026, 3, 10)]
    end

    it 'deploy lens excludes release events' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Ship')
      record(story, 'released', { status: 'released' })

      result = ThroughputScatter.call(team_id: @team.id, action: 'deployed', days: nil)

      assert_empty result.daily_counts
    end

    it 'defaults to released action' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Ship')
      record(story, 'released', { status: 'released' })

      result = ThroughputScatter.call(team_id: @team.id, days: nil)

      assert_equal 1, result.daily_counts[Date.new(2026, 3, 10)]
    end

    it 'defaults to 30 days window' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      old = create_story('Old')
      record(old, 'released', { status: 'released' })

      Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))
      result = ThroughputScatter.call(team_id: @team.id)

      assert_equal Date.new(2026, 3, 16), result.start_date
      assert_equal Date.new(2026, 4, 15), result.end_date
      assert_nil result.daily_counts[Date.new(2026, 3, 1)]
    end

    it 'filters by map_id when provided' do
      map_b = Map.create(team_id: @team.id, name: 'Other', position: 2000)
      activity_b = Activity.create(map_id: map_b.id, team_id: @team.id, name: 'Other', position: 1000)
      task_b = Task.create(
        activity_id: activity_b.id, map_id: map_b.id, team_id: @team.id,
        name: 'Other task', position: 1000
      )

      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s1 = create_story('Map A')
      record(s1, 'released', { status: 'released' })

      s2 = Story.create(
        task_id: task_b.id, map_id: map_b.id, team_id: @team.id,
        title: 'Map B', position: 1000, created_by_id: @alice.id
      )
      record(s2, 'released', { status: 'released' })

      result_a = ThroughputScatter.call(team_id: @team.id, days: nil, map_id: @map.id)
      result_b = ThroughputScatter.call(team_id: @team.id, days: nil, map_id: map_b.id)
      result_all = ThroughputScatter.call(team_id: @team.id, days: nil)

      assert_equal 1, result_a.daily_counts[Date.new(2026, 3, 10)]
      assert_equal 1, result_b.daily_counts[Date.new(2026, 3, 10)]
      assert_equal 2, result_all.daily_counts[Date.new(2026, 3, 10)]
    end
  end
end
