# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/cumulative_flow'
require 'timecop'

describe CumulativeFlow do
  cover 'CumulativeFlow*'
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
      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      assert_empty result.dates
      assert_empty result.planned
    end

    it 'created story counts as planned' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('First')
      record(story, 'created', { title: 'First' })

      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      idx = result.dates.index(Date.new(2026, 3, 10))

      refute_nil idx
      assert_equal 1, result.planned[idx]
      assert_equal 0, result.active[idx]
    end

    it 'activated story moves from planned to active' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Work')
      record(story, 'created', { title: 'Work' })

      Timecop.freeze(Time.utc(2026, 3, 12, 12, 0, 0))
      record(story, 'activated', { reason: 'paired' })

      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      day10 = result.dates.index(Date.new(2026, 3, 10))
      day12 = result.dates.index(Date.new(2026, 3, 12))

      assert_equal 1, result.planned[day10]
      assert_equal 0, result.active[day10]
      assert_equal 0, result.planned[day12]
      assert_equal 1, result.active[day12]
    end

    it 'deployed story moves from active to deployed' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Deploy')
      record(story, 'created', { title: 'Deploy' })
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 11, 12, 0, 0))
      record(story, 'deployed', { deploy_count: 1 })

      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      day11 = result.dates.index(Date.new(2026, 3, 11))

      assert_equal 0, result.active[day11]
      assert_equal 1, result.deployed[day11]
    end

    it 'released story moves to released band' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Ship')
      record(story, 'created', { title: 'Ship' })
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 12, 12, 0, 0))
      record(story, 'released', { status: 'released' })

      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      day12 = result.dates.index(Date.new(2026, 3, 12))

      assert_equal 0, result.active[day12]
      assert_equal 1, result.released[day12]
    end

    it 'deactivated story moves back to planned' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Bounce')
      record(story, 'created', { title: 'Bounce' })
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 11, 12, 0, 0))
      record(story, 'deactivated', { reason: 'no_assignees' })

      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      day11 = result.dates.index(Date.new(2026, 3, 11))

      assert_equal 1, result.planned[day11]
      assert_equal 0, result.active[day11]
    end

    it 'archived story is removed from all bands' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      story = create_story('Gone')
      record(story, 'created', { title: 'Gone' })

      Timecop.freeze(Time.utc(2026, 3, 11, 12, 0, 0))
      record(story, 'archived', { status: 'planned' })

      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      day11 = result.dates.index(Date.new(2026, 3, 11))

      assert_equal 0, result.planned[day11]
      assert_equal 0, result.active[day11]
    end

    it 'multiple stories accumulate correctly' do
      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s1 = create_story('One')
      record(s1, 'created', { title: 'One' })
      s2 = create_story('Two')
      record(s2, 'created', { title: 'Two' })
      record(s1, 'activated', { reason: 'paired' })

      result = CumulativeFlow.call(team_id: @team.id, days: nil)

      day10 = result.dates.index(Date.new(2026, 3, 10))

      assert_equal 1, result.planned[day10]
      assert_equal 1, result.active[day10]
    end

    it 'date range filters to requested window' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      s1 = create_story('Old')
      record(s1, 'created', { title: 'Old' })

      Timecop.freeze(Time.utc(2026, 3, 20, 12, 0, 0))
      s2 = create_story('New')
      record(s2, 'created', { title: 'New' })

      Timecop.freeze(Time.utc(2026, 3, 25, 12, 0, 0))
      result = CumulativeFlow.call(team_id: @team.id, days: 10)

      assert_equal Date.new(2026, 3, 15), result.dates.first
      assert_equal Date.new(2026, 3, 25), result.dates.last

      assert_equal 1, result.planned[0]

      day20 = result.dates.index(Date.new(2026, 3, 20))

      assert_equal 2, result.planned[day20]
    end

    it 'baseline captures pre-window state' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Early')
      record(story, 'created', { title: 'Early' })
      record(story, 'activated', { reason: 'paired' })

      Timecop.freeze(Time.utc(2026, 3, 25, 12, 0, 0))
      result = CumulativeFlow.call(team_id: @team.id, days: 10)

      assert_equal 0, result.planned[0]
      assert_equal 1, result.active[0]
    end

    it 'defaults to 30 days' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Story')
      record(story, 'created', { title: 'Story' })

      Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))
      result = CumulativeFlow.call(team_id: @team.id)

      assert_equal Date.new(2026, 3, 16), result.dates.first
      assert_equal Date.new(2026, 4, 15), result.dates.last
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
      record(s1, 'created', { title: 'Map A' })

      s2 = Story.create(
        task_id: task_b.id, map_id: map_b.id, team_id: @team.id,
        title: 'Map B', position: 1000, created_by_id: @alice.id
      )
      record(s2, 'created', { title: 'Map B' })

      result_a = CumulativeFlow.call(team_id: @team.id, days: nil, map_id: @map.id)
      result_b = CumulativeFlow.call(team_id: @team.id, days: nil, map_id: map_b.id)
      result_all = CumulativeFlow.call(team_id: @team.id, days: nil)

      assert_equal 1, result_a.planned.last
      assert_equal 1, result_b.planned.last
      assert_equal 2, result_all.planned.last
    end
  end
end
