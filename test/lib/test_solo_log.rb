# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/solo_log'
require 'timecop'

describe SoloLog do
  cover 'SoloLog*'
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

  def make_solo_and_release(story, person, released_at: Time.now)
    RecordEvent.call(
      actor_id: person.actor.id, entity: story,
      action: 'collaboration_changed',
      before_state: { mode: 'paired', assignment_count: 2 },
      after_state: { mode: 'solo', assignment_count: 1, person_ids: [person.id], solo_person_id: person.id }
    )
    Timecop.freeze(released_at) do
      story.update(status: 'released', released_at: released_at)
      RecordEvent.call(
        actor_id: person.actor.id, entity: story,
        action: 'released',
        after_state: { status: 'released' }
      )
    end
  end

  def make_paired_and_release(story, people, released_at: Time.now)
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'collaboration_changed',
      before_state: { mode: 'solo', assignment_count: 1 },
      after_state: { mode: 'paired', assignment_count: 2, person_ids: people.map(&:id) }
    )
    Timecop.freeze(released_at) do
      story.update(status: 'released', released_at: released_at)
      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'released',
        after_state: { status: 'released' }
      )
    end
  end

  it 'returns released stories that were always solo' do
    Timecop.freeze(Time.utc(2026, 4, 10, 12, 0, 0))
    story = create_story('Solo ship')
    make_solo_and_release(story, @alice, released_at: Time.utc(2026, 4, 12, 12, 0, 0))

    result = SoloLog.call(team_id: @team.id)

    assert_equal 1, result.length
    entry = result.first

    assert_equal story.id, entry.story_id
    assert_equal 'Solo ship', entry.story_title
    assert_equal 'Alice', entry.person_name
    assert_equal Time.utc(2026, 4, 12, 12, 0, 0), entry.released_at
  end

  it 'excludes stories that were ever paired' do
    Timecop.freeze(Time.utc(2026, 4, 10, 12, 0, 0))
    story = create_story('Paired ship')
    make_paired_and_release(story, [@alice, @bob], released_at: Time.utc(2026, 4, 12, 12, 0, 0))

    result = SoloLog.call(team_id: @team.id)

    assert_empty result
  end

  it 'excludes stories still active (not released)' do
    story = create_story('Still going')
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'collaboration_changed',
      before_state: { mode: 'paired', assignment_count: 2 },
      after_state: { mode: 'solo', assignment_count: 1, person_ids: [@alice.id], solo_person_id: @alice.id }
    )

    result = SoloLog.call(team_id: @team.id)

    assert_empty result
  end

  it 'returns entries ordered by released_at descending' do
    Timecop.freeze(Time.utc(2026, 4, 5, 12, 0, 0))
    s1 = create_story('First solo')
    make_solo_and_release(s1, @alice, released_at: Time.utc(2026, 4, 5, 12, 0, 0))

    s2 = create_story('Second solo')
    make_solo_and_release(s2, @bob, released_at: Time.utc(2026, 4, 10, 12, 0, 0))

    result = SoloLog.call(team_id: @team.id)

    assert_equal 2, result.length
    assert_equal 'Second solo', result[0].story_title
    assert_equal 'First solo', result[1].story_title
  end

  it 'excludes events outside the time window' do
    Timecop.freeze(Time.utc(2026, 1, 1, 12, 0, 0))
    old_story = create_story('Old solo')
    make_solo_and_release(old_story, @alice, released_at: Time.utc(2026, 1, 5, 12, 0, 0))

    Timecop.freeze(Time.utc(2026, 6, 1, 12, 0, 0))
    recent_story = create_story('Recent solo')
    make_solo_and_release(recent_story, @bob, released_at: Time.utc(2026, 6, 1, 12, 0, 0))

    result = SoloLog.call(team_id: @team.id, days: 90)

    assert_equal 1, result.length
    assert_equal 'Recent solo', result.first.story_title
  end

  it 'includes stories that ended solo even if previously ensemble' do
    Timecop.freeze(Time.utc(2026, 4, 10, 12, 0, 0))
    carol = Person.create(name: 'Carol', email: 'carol@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: carol.id)

    story = create_story('Was ensemble')
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'collaboration_changed',
      before_state: { mode: 'paired', assignment_count: 2 },
      after_state: { mode: 'ensemble', assignment_count: 3, person_ids: [@alice.id, @bob.id, carol.id] }
    )
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'collaboration_changed',
      before_state: { mode: 'ensemble', assignment_count: 3 },
      after_state: { mode: 'solo', assignment_count: 1, person_ids: [@alice.id], solo_person_id: @alice.id }
    )
    story.update(status: 'released', released_at: Time.utc(2026, 4, 12, 12, 0, 0))
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'released',
      after_state: { status: 'released' }
    )

    result = SoloLog.call(team_id: @team.id)

    assert_equal 1, result.length
    assert_equal 'Was ensemble', result.first.story_title
    assert_equal 'Alice', result.first.person_name
  end
end
