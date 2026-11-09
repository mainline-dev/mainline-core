# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/shared_rate_limiter'

describe SharedRateLimiter do
  before do
    @prefix = SharedRateLimiter.prefix
    SharedRateLimiter.prefix = "rate_limit:#{SecureRandom.hex(4)}:"
    @now = 1_000_000.0
    @clock = -> { @now }
  end

  after do
    SharedRateLimiter.new(name: 'checks', capacity: 1, refill_rate: 1.0).reset
    SharedRateLimiter.prefix = @prefix
  end

  def limiter(capacity: 5, refill_rate: 1.0)
    SharedRateLimiter.new(name: 'checks', capacity: capacity, refill_rate: refill_rate, clock: @clock)
  end

  it 'allows requests within capacity and rejects the next' do
    checks = limiter

    5.times { assert checks.allow?('key-a') }
    refute checks.allow?('key-a')
  end

  it 'counts keys separately' do
    checks = limiter
    5.times { checks.allow?('key-a') }

    assert checks.allow?('key-b')
  end

  it 'refills over time, never past capacity' do
    checks = limiter
    5.times { checks.allow?('key-a') }

    @now += 2.0

    assert_equal(2, (1..5).count { checks.allow?('key-a') })

    @now += 100.0

    assert_equal(5, (1..6).count { checks.allow?('key-a') })
  end

  it 'shares one count between limiters with the same name, as Puma workers do' do
    first_worker = limiter
    second_worker = limiter

    3.times { first_worker.allow?('key-a') }

    assert_equal(2, (1..5).count { second_worker.allow?('key-a') })
  end

  it 'starts again once reset' do
    checks = limiter
    5.times { checks.allow?('key-a') }

    checks.reset

    assert checks.allow?('key-a')
  end

  it 'lets requests through and reports when Redis cannot be reached' do
    reported = []
    down = ->(*) { raise RedisClient::CannotConnectError, 'connection refused' }

    Sentry.stub(:initialized?, true) do
      Sentry.stub(:capture_exception, ->(e) { reported << e }) do
        Sidekiq.stub(:redis, down) do
          6.times { assert limiter.allow?('key-a') }
        end
      end
    end

    assert_equal 6, reported.size
    assert_kind_of RedisClient::CannotConnectError, reported.first
  end
end
