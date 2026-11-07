# frozen_string_literal: true

require 'digest'
require 'sidekiq'

# At most one login link per email address per WINDOW seconds. Kept in Redis
# so every Puma worker sees the same mark; the key is a hash of the address,
# not the address. The stored value is the send time, so the window follows
# Time.now; Redis's expiry only cleans up.
module LoginLinkThrottle
  WINDOW = 60

  # Each test run sets its own prefix, so overlapping runs sharing one Redis
  # cannot clear each other's marks.
  @prefix = 'login_link_sent:'

  class << self
    attr_accessor :prefix
  end

  def self.allow?(email)
    key = prefix + Digest::SHA256.hexdigest(email)
    now = Time.now.to_f
    Sidekiq.redis do |redis|
      next true if redis.call('SET', key, now.to_s, 'NX', 'EX', WINDOW) == 'OK'
      next false if now - redis.call('GET', key).to_f < WINDOW

      redis.call('SET', key, now.to_s, 'EX', WINDOW)
      true
    end
  end

  def self.reset
    Sidekiq.redis do |redis|
      keys = redis.call('KEYS', "#{prefix}*")
      redis.call('DEL', *keys) unless keys.empty?
    end
  end
end
