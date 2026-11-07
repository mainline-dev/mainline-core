# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/ensemble_timeline'
require 'timecop'

describe EnsembleTimeline do
  cover 'EnsembleTimeline*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @bob   = Person.create(name: 'Bob',   email: 'bob@test.mainline')
    @carol = Person.create(name: 'Carol', email: 'carol@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @alice.id)
    TeamMembership.create(team_id: @team.id, person_id: @bob.id)
    TeamMembership.create(team_id: @team.id, person_id: @carol.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    @persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    @activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: @activity.id, persona_id: @persona.id, team_id: @team.id)
    @task = Task.create(
      activity_id: @activity.id, map_id: @map.id, team_id: @team.id,
      name: 'Search', position: 1000
    )
  end

  after do
    Timecop.return
  end

  def create_story(title)
    pos = (Story.where(task_id: @task.id).max(:position) || 0) + 1000
    Story.create(
      task_id: @task.id, map_id: @map.id, team_id: @team.id,
      title: title, position: pos, created_by_id: @alice.id
    )
  end

  def record_ensemble(story, people, time: Time.now)
    Timecop.freeze(time) do
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'collaboration_changed',
        before_state: { mode: 'paired', assignment_count: 2 },
        after_state: { mode: 'ensemble', assignment_count: people.length, person_ids: people.map(&:id) }
      )
    end
  end

  def record_paired(story, people, time: Time.now)
    Timecop.freeze(time) do
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'collaboration_changed',
        before_state: { mode: 'solo', assignment_count: 1 },
        after_state: { mode: 'paired', assignment_count: 2, person_ids: people.map(&:id) }
      )
    end
  end

  it 'returns ensemble sessions within the last 30 days' do
    Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))
    story = create_story('Ensemble work')
    record_ensemble(story, [@alice, @bob, @carol])

    result = EnsembleTimeline.call(team_id: @team.id)

    assert_equal 1, result.length
    session = result.first

    assert_equal story.id, session.story_id
    assert_equal 'Ensemble work', session.story_title
    assert_equal 3, session.assignment_count
    assert_includes session.person_names, 'Alice'
    assert_includes session.person_names, 'Bob'
    assert_includes session.person_names, 'Carol'
  end

  it 'excludes paired sessions (only 2 people)' do
    Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))
    story = create_story('Pair work')
    record_paired(story, [@alice, @bob])

    result = EnsembleTimeline.call(team_id: @team.id)

    assert_empty result
  end

  it 'excludes sessions older than the requested days' do
    old_time = Time.utc(2026, 2, 1, 12, 0, 0)
    story = create_story('Old ensemble')
    record_ensemble(story, [@alice, @bob, @carol], time: old_time)

    Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))
    result = EnsembleTimeline.call(team_id: @team.id, days: 30)

    assert_empty result
  end

  it 'returns sessions ordered by most recent first' do
    Timecop.freeze(Time.utc(2026, 4, 10, 12, 0, 0))
    s1 = create_story('First ensemble')
    record_ensemble(s1, [@alice, @bob, @carol], time: Time.utc(2026, 4, 10, 12, 0, 0))

    s2 = create_story('Second ensemble')
    record_ensemble(s2, [@alice, @bob, @carol], time: Time.utc(2026, 4, 12, 12, 0, 0))

    Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))
    result = EnsembleTimeline.call(team_id: @team.id)

    assert_equal 'Second ensemble', result[0].story_title
    assert_equal 'First ensemble', result[1].story_title
  end

  it 'respects custom days parameter' do
    story = create_story('Recent ensemble')
    record_ensemble(story, [@alice, @bob, @carol], time: Time.utc(2026, 4, 10, 12, 0, 0))

    Timecop.freeze(Time.utc(2026, 4, 15, 12, 0, 0))

    result_5 = EnsembleTimeline.call(team_id: @team.id, days: 5)

    assert_equal 1, result_5.length

    result_3 = EnsembleTimeline.call(team_id: @team.id, days: 3)

    assert_empty result_3
  end
end
