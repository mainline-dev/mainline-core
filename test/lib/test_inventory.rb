# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/business_days'
require_relative '../../lib/inventory'
require 'timecop'

describe Inventory do
  cover 'Inventory*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @alice.id)
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
      title: title, position: pos, status: 'active',
      created_by_id: @alice.id
    )
  end

  def deploy_story(story, at:)
    count = story.deploy_count + 1
    updates = { deploy_count: count, last_deployed_at: at }
    updates[:first_deployed_at] = at if story.deploy_count.zero?
    DB[:stories].where(id: story.id).update(updates)
    story.refresh
  end

  it 'returns deployed-but-unreleased stories' do
    Timecop.freeze(Time.utc(2026, 4, 20, 12, 0, 0))
    story = create_story('Deployed')
    deploy_story(story, at: Time.utc(2026, 4, 20, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal 1, result.items.length
    assert_equal story.id, result.items.first.story.id
  end

  it 'excludes released stories' do
    Timecop.freeze(Time.utc(2026, 4, 20, 12, 0, 0))
    story = create_story('Released')
    deploy_story(story, at: Time.utc(2026, 4, 18, 10, 0, 0))
    story.update(status: 'released', released_at: Time.utc(2026, 4, 19, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_empty result.items
  end

  it 'excludes stories never deployed' do
    create_story('Never deployed')

    result = Inventory.call(team_id: @team.id)

    assert_empty result.items
  end

  it 'classifies as in_flight within threshold' do
    Timecop.freeze(Time.utc(2026, 4, 22, 12, 0, 0))
    story = create_story('Fresh deploy')
    deploy_story(story, at: Time.utc(2026, 4, 21, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal :in_flight, result.items.first.band
  end

  it 'classifies as aging between thresholds' do
    Timecop.freeze(Time.utc(2026, 4, 28, 12, 0, 0))
    story = create_story('Aging deploy')
    deploy_story(story, at: Time.utc(2026, 4, 21, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal :aging, result.items.first.band
    assert_equal 5, result.items.first.business_days_since_deploy
  end

  it 'classifies as stale beyond stale threshold' do
    Timecop.freeze(Time.utc(2026, 4, 28, 12, 0, 0))
    story = create_story('Stale deploy')
    deploy_story(story, at: Time.utc(2026, 4, 10, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal :stale, result.items.first.band
  end

  it 'classifies as in_flight at 3 business days (one below default aging threshold)' do
    Timecop.freeze(Time.utc(2026, 4, 23, 12, 0, 0))
    story = create_story('Just under')
    deploy_story(story, at: Time.utc(2026, 4, 20, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal :in_flight, result.items.first.band
    assert_equal 3, result.items.first.business_days_since_deploy
  end

  it 'classifies as aging at exactly 4 business days (default aging threshold)' do
    Timecop.freeze(Time.utc(2026, 4, 24, 12, 0, 0))
    story = create_story('At boundary')
    deploy_story(story, at: Time.utc(2026, 4, 20, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal :aging, result.items.first.band
    assert_equal 4, result.items.first.business_days_since_deploy
  end

  it 'respects custom team thresholds' do
    Timecop.freeze(Time.utc(2026, 4, 23, 12, 0, 0))
    story = create_story('Custom threshold')
    deploy_story(story, at: Time.utc(2026, 4, 21, 10, 0, 0))

    TeamConstraint.create(
      team_id: @team.id, constraint_key: 'inventory_aging_days',
      value: 2, min_value: 1, max_value: 30, default_value: 4
    )

    result = Inventory.call(team_id: @team.id)

    assert_equal :aging, result.items.first.band
  end

  it 'counts business days only (skips weekends)' do
    friday = Time.utc(2026, 4, 17, 16, 0, 0)
    monday = Time.utc(2026, 4, 20, 10, 0, 0)
    Timecop.freeze(monday)
    story = create_story('Weekend deploy')
    deploy_story(story, at: friday)

    result = Inventory.call(team_id: @team.id)

    assert_equal 1, result.items.first.business_days_since_deploy
  end

  it 'returns summary counts' do
    Timecop.freeze(Time.utc(2026, 4, 28, 12, 0, 0))

    fresh = create_story('Fresh')
    deploy_story(fresh, at: Time.utc(2026, 4, 28, 8, 0, 0))

    aging = create_story('Aging')
    deploy_story(aging, at: Time.utc(2026, 4, 21, 10, 0, 0))

    stale = create_story('Stale')
    deploy_story(stale, at: Time.utc(2026, 4, 10, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal 1, result.in_flight
    assert_equal 1, result.aging
    assert_equal 1, result.stale
  end

  it 'returns entries sorted by last_deployed_at ascending' do
    Timecop.freeze(Time.utc(2026, 4, 28, 12, 0, 0))

    newer = create_story('Newer')
    deploy_story(newer, at: Time.utc(2026, 4, 25, 10, 0, 0))

    older = create_story('Older')
    deploy_story(older, at: Time.utc(2026, 4, 15, 10, 0, 0))

    result = Inventory.call(team_id: @team.id)

    assert_equal 'Older', result.items.first.story.title
    assert_equal 'Newer', result.items.last.story.title
  end

  it 'skips stories with nil last_deployed_at' do
    Timecop.freeze(Time.utc(2026, 4, 20, 12, 0, 0))
    good = create_story('Good')
    deploy_story(good, at: Time.utc(2026, 4, 20, 10, 0, 0))

    bad = create_story('Bad')
    bad_vals = bad.values.merge(deploy_count: 1, first_deployed_at: nil, last_deployed_at: nil)
    fake_bad = Struct.new(*bad_vals.keys, keyword_init: true).new(**bad_vals)

    Inventory.stub(:deployed_stories, [good.refresh, fake_bad]) do
      result = Inventory.call(team_id: @team.id)

      assert_equal 1, result.items.length
      assert_equal 'Good', result.items.first.story.title
    end
  end
end
