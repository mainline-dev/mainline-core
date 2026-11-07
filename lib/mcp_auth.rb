# frozen_string_literal: true

require 'bcrypt'
require 'digest'
require 'sidekiq'

module McpAuth
  TTL = 300

  def self.valid?(team, token)
    return false unless team.mcp_token && token

    token_hash = Digest::SHA256.hexdigest(token.to_s)
    cache_key = "mcp_auth:#{team.id}:#{token_hash}"

    cached = begin
      Sidekiq.redis { |c| c.call('GET', cache_key) }
    rescue StandardError
      nil
    end
    return true if cached == '1'

    return false unless BCrypt::Password.new(team.mcp_token) == token.to_s

    begin
      Sidekiq.redis { |c| c.call('SET', cache_key, '1', 'EX', TTL) }
    rescue StandardError
      nil
    end
    true
  end

  def self.clear_cache(team_id)
    Sidekiq.redis do |c|
      keys = c.call('KEYS', "mcp_auth:#{team_id}:*")
      keys.each { |k| c.call('DEL', k) } if keys.any?
    end
  rescue StandardError
    nil
  end
end
