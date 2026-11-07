# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/rate_limiter'

describe RateLimiter do
  cover 'RateLimiter*'
  before do
    @now = 1000.0
    @clock = -> { @now }
    @limiter = RateLimiter.new(capacity: 5, refill_rate: 1.0, clock: @clock)
  end

  it 'allows requests within capacity' do
    5.times { assert @limiter.allow?('key-a') }
  end

  it 'rejects requests exceeding capacity' do
    5.times { @limiter.allow?('key-a') }

    refute @limiter.allow?('key-a')
  end

  it 'tracks keys independently' do
    5.times { @limiter.allow?('key-a') }

    assert @limiter.allow?('key-b')
  end

  it 'refills tokens over time' do
    5.times { @limiter.allow?('key-a') }

    refute @limiter.allow?('key-a')

    @now += 2.0

    assert @limiter.allow?('key-a')
  end

  it 'never exceeds capacity on refill' do
    5.times { @limiter.allow?('key-a') }

    @now += 100.0
    count = (1..6).count { @limiter.allow?('key-a') }

    assert_equal 5, count
  end

  it 'evicts oldest key when max_keys exceeded' do
    limiter = RateLimiter.new(capacity: 5, refill_rate: 1.0, clock: @clock, max_keys: 3)
    limiter.allow?('a')
    @now += 1.0
    limiter.allow?('b')
    @now += 1.0
    limiter.allow?('c')
    @now += 1.0
    limiter.allow?('d')

    assert_equal 3, limiter.size
  end

  it 'sweeps stale entries after sweep interval' do
    limiter = RateLimiter.new(
      capacity: 5, refill_rate: 1.0, clock: @clock,
      max_keys: 100, sweep_interval: 600, stale_after: 1800
    )
    limiter.allow?('old')
    @now += 1801.0
    limiter.allow?('new')

    assert_equal 1, limiter.size
  end

  it 'does not sweep before interval elapses' do
    limiter = RateLimiter.new(
      capacity: 5, refill_rate: 1.0, clock: @clock,
      max_keys: 100, sweep_interval: 600, stale_after: 1800
    )
    limiter.allow?('old')
    @now += 599.0
    limiter.allow?('new')

    assert_equal 2, limiter.size
  end

  it 'global limiter rejects after capacity exhausted' do
    limiter = RateLimiter.new(capacity: 60, refill_rate: 1.0, clock: @clock)
    60.times { limiter.allow?('global') }

    refute limiter.allow?('global')
  end

  it 'evicts the least recently used key' do
    limiter = RateLimiter.new(capacity: 5, refill_rate: 0.0, clock: @clock, max_keys: 2)
    5.times { limiter.allow?('a') }
    @now += 1.0
    5.times { limiter.allow?('b') }
    @now += 1.0
    limiter.allow?('c')

    refute limiter.allow?('b'), 'b should still be rate-limited (not evicted)'
    assert limiter.allow?('a'), 'a should have been evicted and get a fresh bucket'
  end
end
