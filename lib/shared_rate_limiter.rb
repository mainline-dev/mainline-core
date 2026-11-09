# frozen_string_literal: true

require 'digest'
require 'sentry-ruby'
require 'sidekiq'

# A token bucket kept in Redis, so every Puma worker and every app instance
# shares one count, and a restart does not reset it. Each check is one Lua
# script, so two workers checking at once cannot both take the last token.
# Keys are hashed, so no email address or IP is stored.
#
# If Redis cannot be reached the request is let through and the error goes to
# Sentry: Sidekiq is down with it, and locking everyone out of sign-in as well
# would make the outage worse.
class SharedRateLimiter
  TAKE = <<~LUA
    local capacity, rate, now, ttl = tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3]), tonumber(ARGV[4])
    local bucket = redis.call('HMGET', KEYS[1], 'tokens', 'last')
    local tokens, last = tonumber(bucket[1]), tonumber(bucket[2])
    if tokens == nil then tokens, last = capacity, now end
    tokens = math.min(capacity, tokens + math.max(0, now - last) * rate)
    local allowed = 0
    if tokens >= 1 then
      tokens = tokens - 1
      allowed = 1
    end
    redis.call('HSET', KEYS[1], 'tokens', tostring(tokens), 'last', tostring(now))
    redis.call('EXPIRE', KEYS[1], ttl)
    return allowed
  LUA

  # Each test run sets its own prefix, so overlapping runs sharing one Redis
  # cannot clear each other's counts.
  @prefix = 'rate_limit:'

  class << self
    attr_accessor :prefix
  end

  def initialize(name:, capacity:, refill_rate:, clock: -> { Time.now.to_f })
    @name = name
    @capacity = capacity
    @refill_rate = refill_rate
    @clock = clock
    # A bucket untouched this long has refilled; Redis forgets it then.
    @ttl = (capacity / refill_rate).ceil + 1
  end

  def allow?(key)
    taken = Sidekiq.redis { |redis| redis.call('EVAL', TAKE, 1, bucket(key), @capacity, @refill_rate, @clock.call, @ttl) }
    taken == 1
  rescue RedisClient::Error => e
    Sentry.capture_exception(e) if Sentry.initialized?
    true
  end

  def reset
    Sidekiq.redis do |redis|
      keys = redis.call('KEYS', "#{namespace}*")
      redis.call('DEL', *keys) unless keys.empty?
    end
  end

  private

  def namespace
    "#{self.class.prefix}#{@name}:"
  end

  def bucket(key)
    namespace + Digest::SHA256.hexdigest(key.to_s)
  end
end
