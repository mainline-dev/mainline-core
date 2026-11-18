# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/change_team_constraint'

describe ChangeTeamConstraint do
  cover 'ChangeTeamConstraint*'

  before do
    @team = Team.create(name: 'Payments')
    @other = Team.create(name: 'Mobile')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
  end

  def aging(value)
    { key: 'inventory_aging_days', value: value, min: 1, max: 30, default: 4 }
  end

  def stale(value)
    { key: 'inventory_stale_days', value: value, min: 2, max: 60, default: 10 }
  end

  def change(*settings, team: @team, reason: nil, &)
    ChangeTeamConstraint.call(team: team, actor: @alice.actor, settings: settings, reason: reason, &)
  end

  def rows(team = @team)
    TeamConstraint.where(team_id: team.id).order(:constraint_key).all.map { |row|
      row.values.values_at(:constraint_key, :value, :min_value, :max_value, :default_value)
    }
  end

  def events(team = @team)
    Event.where(team_id: team.id, entity_type: 'team_constraint', action: 'updated').order(:event_no).all
  end

  it 'saves a setting with its bounds, and records what it was by default and became, for the team, by whoever changed it' do
    change(aging(6))
    row = TeamConstraint.first(team_id: @team.id, constraint_key: 'inventory_aging_days')

    assert_equal [['inventory_aging_days', 6, 1, 30, 4]], rows
    assert_equal([[row.id, @alice.actor.id]], events.map { |event| [event.entity_id, event.actor_id] })
    assert_equal [{ 'constraint_key' => 'inventory_aging_days', 'value' => 4 }], events.map(&:before_state)
    assert_equal [{ 'constraint_key' => 'inventory_aging_days', 'value' => 6 }], events.map(&:after_state)
  end

  it 'changes a setting already saved, in the same row, and records what it was' do
    change(aging(6))
    change(aging(9))

    assert_equal [['inventory_aging_days', 9, 1, 30, 4]], rows
    assert_equal([[4, 6], [6, 9]], events.map { |event| [event.before_state['value'], event.after_state['value']] })
  end

  it 'records nothing for a setting saved as it already was, whether by default or not' do
    change(aging(4))
    change(aging(4))

    assert_equal [['inventory_aging_days', 4, 1, 30, 4]], rows
    assert_empty events
  end

  it 'records the reason when one is given' do
    change(aging(6), reason: 'Releases are weekly now')

    assert_equal 'Releases are weekly now', events.first.after_state['reason']
  end

  it 'saves several settings together, each with its own record, then does what must happen with them' do
    done = []

    change(aging(6), stale(12)) { done << rows }
    row_ids = %w[inventory_aging_days inventory_stale_days].map { |key| TeamConstraint.first(team_id: @team.id, constraint_key: key).id }

    assert_equal [['inventory_aging_days', 6, 1, 30, 4], ['inventory_stale_days', 12, 2, 60, 10]], rows
    assert_equal(%w[inventory_aging_days inventory_stale_days], events.map { |event| event.after_state['constraint_key'] })
    assert_equal [rows, row_ids], [done.first, events.map(&:entity_id)]
  end

  it "leaves another team's setting of the same name as it is" do
    SetTeamContext.call(@other.id)
    change(aging(8), team: @other)
    SetTeamContext.call(@team.id)

    change(aging(6))
    ours = events.map { |event| event.before_state['value'] }
    SetTeamContext.call(@other.id)

    assert_equal [[4], [['inventory_aging_days', 8, 1, 30, 4]], 1], [ours, rows(@other), events(@other).size]
  end
end
