# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/mcp_auth'

describe McpAuth do
  before do
    @team = Team.create(name: 'Auth test')
    SetTeamContext.call(@team.id)
    @raw_token = SecureRandom.hex(32)
    @team.update(mcp_token: BCrypt::Password.create(@raw_token))
    @team.refresh
  end

  after do
    McpAuth.clear_cache(@team.id)
  end

  it 'validates a correct token' do
    assert McpAuth.valid?(@team, @raw_token)
  end

  it 'rejects a wrong token' do
    refute McpAuth.valid?(@team, 'wrong')
  end

  it 'rejects when team has no MCP token' do
    @team.update(mcp_token: nil)
    @team.refresh

    refute McpAuth.valid?(@team, @raw_token)
  end

  it 'skips BCrypt on second call' do
    McpAuth.valid?(@team, @raw_token)

    bcrypt_called = false
    original_new = BCrypt::Password.method(:new)
    BCrypt::Password.define_singleton_method(:new) do |*args|
      bcrypt_called = true
      original_new.call(*args)
    end

    assert McpAuth.valid?(@team, @raw_token)
    refute bcrypt_called, 'BCrypt should not be called on cache hit'
  ensure
    BCrypt::Password.define_singleton_method(:new, original_new)
  end

  it 'invalidates cache when cleared' do
    McpAuth.valid?(@team, @raw_token)
    McpAuth.clear_cache(@team.id)

    bcrypt_called = false
    original_new = BCrypt::Password.method(:new)
    BCrypt::Password.define_singleton_method(:new) do |*args|
      bcrypt_called = true
      original_new.call(*args)
    end

    assert McpAuth.valid?(@team, @raw_token)
    assert bcrypt_called, 'BCrypt should be called after cache clear'
  ensure
    BCrypt::Password.define_singleton_method(:new, original_new)
  end
end
