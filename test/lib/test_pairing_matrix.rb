# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/pairing_matrix'
require_relative '../../lib/mcp_actor'
require 'timecop'

describe PairingMatrix do
  cover 'PairingMatrix*'
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

  def collab_mode(count)
    case count
    when 0 then 'planned'
    when 1 then 'solo'
    when 2 then 'paired'
    else 'ensemble'
    end
  end

  def assign(story, person)
    before_count = StoryAssignment.where(story_id: story.id).count
    StoryAssignment.create(story_id: story.id, person_id: person.id, team_id: @team.id)
    RecordEvent.call(
      actor_id: person.actor.id, entity: story,
      action: 'person_assigned',
      after_state: { person_id: person.id }
    )
    after_count = before_count + 1
    record_collab_change(story, before_count, after_count) if after_count >= 2 && collab_mode(before_count) != collab_mode(after_count)
  end

  def unassign(story, person)
    before_count = StoryAssignment.where(story_id: story.id).count
    StoryAssignment.where(story_id: story.id, person_id: person.id).first&.destroy
    after_count = before_count - 1
    record_collab_change(story, before_count, after_count) if after_count >= 1 && collab_mode(before_count) != collab_mode(after_count)
  end

  def release_assignments(story)
    StoryAssignment.where(story_id: story.id).each(&:destroy)
  end

  def record_collab_change(story, before_count, after_count)
    ids = StoryAssignment.where(story_id: story.id).select_map(:person_id)
    after_mode = collab_mode(after_count)
    after_state = { mode: after_mode, assignment_count: after_count, person_ids: ids }
    after_state[:solo_person_id] = ids.first if after_mode == 'solo'
    RecordEvent.call(
      actor_id: @alice.actor.id, entity: story,
      action: 'collaboration_changed',
      before_state: { mode: collab_mode(before_count), assignment_count: before_count },
      after_state: after_state
    )
  end

  def pair_key(person_a, person_b)
    [person_a.id, person_b.id].sort
  end

  def agent_reads(story, with:)
    RecordEvent.call(
      actor_id: McpActor.id_for(@team.id), entity: story,
      action: 'agent_read',
      after_state: { person_ids: with.map(&:id) }
    )
  end

  def agent_key(result, person)
    [person.id, result.agent.id].sort
  end

  describe '.call' do
    it 'returns team members ordered by name' do
      result = PairingMatrix.call(team_id: @team.id)

      assert_equal %w[Alice Bob], result.people.map(&:name)
    end

    it 'two people on same story shows days_since = 0 when frozen' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Paired work')
      assign(story, @alice)
      assign(story, @bob)

      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 0, result.pairs[pair_key(@alice, @bob)]
    end

    it 'two people never paired have no entry in pairs' do
      result = PairingMatrix.call(team_id: @team.id)

      assert_nil result.pairs[pair_key(@alice, @bob)]
    end

    it 'multiple shared stories uses most recent' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      s1 = create_story('First')
      assign(s1, @alice)
      assign(s1, @bob)
      release_assignments(s1)

      Timecop.freeze(Time.utc(2026, 3, 10, 12, 0, 0))
      s2 = create_story('Second')
      assign(s2, @alice)
      assign(s2, @bob)

      Timecop.freeze(Time.utc(2026, 3, 15, 12, 0, 0))
      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 5, result.pairs[pair_key(@alice, @bob)]
    end

    it 'ensemble generates all pairs' do
      carol = Person.create(name: 'Carol', email: 'carol@test.mainline')
      TeamMembership.create(team_id: @team.id, person_id: carol.id)

      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Ensemble')
      assign(story, @alice)
      assign(story, @bob)
      assign(story, carol)

      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 0, result.pairs[pair_key(@alice, @bob)]
      assert_equal 0, result.pairs[pair_key(@alice, carol)]
      assert_equal 0, result.pairs[pair_key(@bob, carol)]
    end

    it 'tracks story count per pair' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      s1 = create_story('First')
      assign(s1, @alice)
      assign(s1, @bob)
      release_assignments(s1)

      s2 = create_story('Second')
      assign(s2, @alice)
      assign(s2, @bob)

      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 2, result.story_counts[pair_key(@alice, @bob)]
    end

    it 'transient pairing under 1 day does not count' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Brief pair')
      assign(story, @alice)
      assign(story, @bob)

      Timecop.freeze(Time.utc(2026, 3, 1, 18, 0, 0))
      unassign(story, @bob)

      result = PairingMatrix.call(team_id: @team.id)

      assert_nil result.pairs[pair_key(@alice, @bob)]
      assert_equal 0, result.story_counts.fetch(pair_key(@alice, @bob), 0)
    end

    it 'transient pairing >= 1 day counts' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Longer pair')
      assign(story, @alice)
      assign(story, @bob)

      Timecop.freeze(Time.utc(2026, 3, 3, 12, 0, 0))
      unassign(story, @bob)

      Timecop.freeze(Time.utc(2026, 3, 5, 12, 0, 0))
      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 1, result.story_counts[pair_key(@alice, @bob)]

      refute_nil result.pairs[pair_key(@alice, @bob)]
    end

    it 'transient pairing with deploy counts' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Deploy pair')
      assign(story, @alice)
      assign(story, @bob)

      RecordEvent.call(
        actor_id: @alice.actor.id, entity: story,
        action: 'deployed',
        after_state: { deploy_count: 1 }
      )

      unassign(story, @bob)

      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 1, result.story_counts[pair_key(@alice, @bob)]

      refute_nil result.pairs[pair_key(@alice, @bob)]
    end

    it 'current_pairs shows only live assignments' do
      story = create_story('Active pair')
      assign(story, @alice)
      assign(story, @bob)

      result = PairingMatrix.call(team_id: @team.id)

      assert result.current_pairs[pair_key(@alice, @bob)]
    end

    it 'current_pairs excludes released stories' do
      story = create_story('Done')
      assign(story, @alice)
      assign(story, @bob)
      release_assignments(story)

      result = PairingMatrix.call(team_id: @team.id)

      refute result.current_pairs[pair_key(@alice, @bob)]
    end

    it 'current_solos includes person assigned alone' do
      story = create_story('Solo work')
      StoryAssignment.create(story_id: story.id, person_id: @alice.id, team_id: @team.id)

      result = PairingMatrix.call(team_id: @team.id)

      assert_includes result.current_solos, @alice.id
      refute_includes result.current_solos, @bob.id
    end

    it 'no assignments returns empty result' do
      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 2, result.people.length
      assert_empty result.pairs
    end

    it 'excludes events outside the time window' do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 0, 0))
      old_story = create_story('Old pair')
      assign(old_story, @alice)
      assign(old_story, @bob)
      release_assignments(old_story)

      Timecop.freeze(Time.utc(2026, 6, 1, 12, 0, 0))
      recent_story = create_story('Recent pair')
      assign(recent_story, @alice)
      assign(recent_story, @bob)

      result = PairingMatrix.call(team_id: @team.id, days: 90)

      assert_equal 1, result.story_counts[pair_key(@alice, @bob)]
    end

    it 'skips collaboration events with nil after_state' do
      story = create_story('Corrupt event')
      assign(story, @alice)
      assign(story, @bob)

      DB[:events].insert(
        team_id: @team.id, entity_id: story.id, entity_type: 'storie',
        action: 'collaboration_changed', actor_id: @alice.actor.id,
        map_id: @map.id, occurred_at: Time.now,
        before_state: Sequel.pg_json_wrap({}),
        after_state: Sequel.pg_json_wrap(nil)
      )

      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 1, result.story_counts[pair_key(@alice, @bob)]
    end

    it 'includes all events with days: 365' do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 0, 0))
      old_story = create_story('Old pair')
      assign(old_story, @alice)
      assign(old_story, @bob)
      release_assignments(old_story)

      Timecop.freeze(Time.utc(2026, 6, 1, 12, 0, 0))
      recent_story = create_story('Recent pair')
      assign(recent_story, @alice)
      assign(recent_story, @bob)

      result = PairingMatrix.call(team_id: @team.id, days: 365)

      assert_equal 2, result.story_counts[pair_key(@alice, @bob)]
    end
    it 'has no agent until an agent has read a story' do
      assert_nil PairingMatrix.call(team_id: @team.id).agent
    end

    it 'counts the stories an agent read while a person was on them, once each' do
      story = create_story('Read twice')
      assign(story, @alice)
      agent_reads(story, with: [@alice])
      agent_reads(story, with: [@alice])
      release_assignments(story)
      other = create_story('Read once')
      assign(other, @alice)
      agent_reads(other, with: [@alice])

      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 'AI Agent', result.agent.name
      assert_equal 2, result.story_counts[agent_key(result, @alice)]
      assert_nil result.story_counts[agent_key(result, @bob)]
    end

    it 'agent days count from the last read with that person' do
      Timecop.freeze(Time.utc(2026, 3, 1, 12, 0, 0))
      story = create_story('Read')
      assign(story, @alice)
      agent_reads(story, with: [@alice])

      Timecop.freeze(Time.utc(2026, 3, 4, 12, 0, 0))
      result = PairingMatrix.call(team_id: @team.id)

      assert_equal 3, result.pairs[agent_key(result, @alice)]
    end

    it 'agent reads outside the window do not count' do
      Timecop.freeze(Time.utc(2026, 1, 1, 12, 0, 0))
      story = create_story('Old read')
      assign(story, @alice)
      agent_reads(story, with: [@alice])

      Timecop.freeze(Time.utc(2026, 9, 1, 12, 0, 0))
      result = PairingMatrix.call(team_id: @team.id)

      assert_nil result.agent
    end
  end
end
