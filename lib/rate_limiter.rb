# frozen_string_literal: true

class RateLimiter
  def initialize(capacity:, refill_rate:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                 max_keys: nil, sweep_interval: nil, stale_after: nil)
    @capacity = capacity
    @refill_rate = refill_rate
    @clock = clock
    @max_keys = max_keys
    @sweep_interval = sweep_interval
    @stale_after = stale_after
    @buckets = {}
    @last_sweep = clock.call
    @mutex = Mutex.new
  end

  def reset
    @mutex.synchronize { @buckets.clear }
  end

  def size
    @mutex.synchronize { @buckets.size }
  end

  def allow?(key)
    @mutex.synchronize do
      now = @clock.call
      sweep(now)
      bucket = @buckets.delete(key)

      if bucket
        elapsed = now - bucket[:last]
        bucket[:tokens] = [bucket[:tokens] + (elapsed * @refill_rate), @capacity].min
        bucket[:last] = now
      else
        evict_oldest if @max_keys && @buckets.size >= @max_keys
        bucket = { tokens: @capacity.to_f, last: now }
      end

      @buckets[key] = bucket

      if bucket[:tokens] >= 1.0
        bucket[:tokens] -= 1.0
        true
      else
        false
      end
    end
  end

  private

  def sweep(now)
    return unless @sweep_interval && @stale_after
    return if now - @last_sweep < @sweep_interval

    @last_sweep = now
    cutoff = now - @stale_after
    @buckets.delete_if { |_, b| b[:last] < cutoff }
  end

  def evict_oldest
    @buckets.delete(@buckets.each_key.first)
  end
end
