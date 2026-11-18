# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/archive_activity'

describe ArchiveActivity do
  cover 'ArchiveActivity*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    @checkout = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    # Another activity with a step of its own, which must not hold this one back.
    @browse = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 2000)
    step('Search', @browse)
    @now = Time.utc(2030, 1, 7, 9)
  end

  def step(name, activity)
    Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: name, position: 1000)
  end

  def archive
    ArchiveActivity.call(activity: @checkout.refresh, actor: @person.actor, now: @now)
  end

  def recorded
    Event.where(entity_id: @checkout.id, action: 'archived').all
  end

  it 'archives an activity with no steps, and records it by name' do
    result = archive
    by = recorded.map { |event| [event.actor_id, event.after_state] }

    assert_equal [true, nil], [result.success?, result.error]
    assert_equal [@now, nil], [@checkout.refresh.archived_at, @browse.refresh.archived_at]
    assert_equal [[@person.actor.id, { 'name' => 'Checkout' }]], by
  end

  it 'refuses an activity that still has a step, saying why, and archives it once the step is archived' do
    pay = step('Pay', @checkout)
    refused = archive
    held = [refused.success?, @checkout.refresh.archived_at, recorded.size]
    pay.update(archived_at: Time.now)

    assert_equal [false, nil, 0], held
    refute_empty refused.error.to_s
    assert_predicate archive, :success?
  end
end
