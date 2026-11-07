# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/resource_cap'

describe ResourceCap do
  cover 'ResourceCap*'

  it 'returns ok below soft cap' do
    assert_equal :ok, ResourceCap.check(count: 999, soft: 1000, hard: 2000)
  end

  it 'returns warning at soft cap' do
    assert_equal :warning, ResourceCap.check(count: 1000, soft: 1000, hard: 2000)
  end

  it 'returns warning between soft and hard' do
    assert_equal :warning, ResourceCap.check(count: 1500, soft: 1000, hard: 2000)
  end

  it 'returns blocked at hard cap' do
    assert_equal :blocked, ResourceCap.check(count: 2000, soft: 1000, hard: 2000)
  end

  it 'returns blocked above hard cap' do
    assert_equal :blocked, ResourceCap.check(count: 2001, soft: 1000, hard: 2000)
  end

  describe '.stories_per_map' do
    it 'checks story count for a map' do
      assert_equal :ok, ResourceCap.stories_per_map(0)
    end

    it 'warns at soft cap' do
      assert_equal :warning, ResourceCap.stories_per_map(1000)
    end

    it 'blocks at hard cap' do
      assert_equal :blocked, ResourceCap.stories_per_map(2000)
    end
  end

  describe '.maps_per_team' do
    it 'checks map count for a team' do
      assert_equal :ok, ResourceCap.maps_per_team(0)
    end

    it 'warns at soft cap' do
      assert_equal :warning, ResourceCap.maps_per_team(40)
    end

    it 'blocks at hard cap' do
      assert_equal :blocked, ResourceCap.maps_per_team(80)
    end
  end

  describe '.teams_per_person' do
    it 'checks team count for a person' do
      assert_equal :ok, ResourceCap.teams_per_person(0)
    end

    it 'warns at soft cap' do
      assert_equal :warning, ResourceCap.teams_per_person(10)
    end

    it 'blocks at hard cap' do
      assert_equal :blocked, ResourceCap.teams_per_person(20)
    end
  end
end
