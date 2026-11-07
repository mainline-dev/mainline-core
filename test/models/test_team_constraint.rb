# frozen_string_literal: true

require_relative '../model_spec_helper'

describe TeamConstraint do
  cover 'TeamConstraint*'
  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
  end

  describe '.for_team' do
    it 'returns default when no row exists' do
      result = TeamConstraint.for_team(@team.id, 'inventory_aging_days', default: 4)

      assert_equal 4, result
    end

    it 'returns stored value when row exists' do
      DB[:team_constraints].insert(
        id: Sequel.lit('gen_random_uuid()'),
        team_id: @team.id, constraint_key: 'inventory_aging_days',
        value: 7, min_value: 1, max_value: 30, default_value: 4,
        updated_at: Sequel.lit('now()')
      )

      result = TeamConstraint.for_team(@team.id, 'inventory_aging_days', default: 4)

      assert_equal 7, result
    end

    it 'returns default when row exists but value is nil' do
      DB[:team_constraints].insert(
        id: Sequel.lit('gen_random_uuid()'),
        team_id: @team.id, constraint_key: 'inventory_aging_days',
        value: 7, min_value: 1, max_value: 30, default_value: 4,
        updated_at: Sequel.lit('now()')
      )
      row = TeamConstraint.where(team_id: @team.id, constraint_key: 'inventory_aging_days').first
      row.define_singleton_method(:value) { nil }

      fake = Object.new
      fake.define_singleton_method(:first) { row }
      TeamConstraint.stub(:where, fake) do
        result = TeamConstraint.for_team(@team.id, 'inventory_aging_days', default: 4)

        assert_equal 4, result
      end
    end

    it 'returns zero when stored value is zero' do
      DB[:team_constraints].insert(
        id: Sequel.lit('gen_random_uuid()'),
        team_id: @team.id, constraint_key: 'allow_solo_activation',
        value: 0, min_value: 0, max_value: 1, default_value: 0,
        updated_at: Sequel.lit('now()')
      )

      result = TeamConstraint.for_team(@team.id, 'allow_solo_activation', default: 0)

      assert_equal 0, result
    end
  end
end
