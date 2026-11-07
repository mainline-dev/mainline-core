# test/test_helper.rb
# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'minitest/hooks/default'
require 'minitest/mock'
require 'mutant/minitest/coverage'

parent_pid = Process.pid
at_exit do
  ARGV.clear if Process.pid != parent_pid || defined?(Mutant)
end

module Minitest::Hooks::ClassMethods
  alias _original_new new
  def new(name)
    if !name.equal?(NEW) && @instance.nil?
      DB.disconnect
      @instance = _original_new(NEW)
      @instance.time = 0
    end
    _original_new(name)
  end
end

class Minitest::HooksSpec
  # Outer transaction wraps the entire describe block.
  # Inner savepoint wraps each individual test.
  # Both roll back. DB is always clean.
  around(:all) do |&block|
    DB.transaction(rollback: :always) { super(&block) }
  end

  around do |&block|
    DB.transaction(rollback: :always, savepoint: true, auto_savepoint: true) { super(&block) }
  end

  # Toggle DB logging for debugging a specific test:
  #   log { create_story(...) }
  def log
    LOGGER.level = Logger::INFO
    yield
  ensure
    LOGGER.level = Logger::FATAL
  end
end

freeze_core = false
if freeze_core
  at_exit do
    require 'refrigerator'
    Refrigerator.freeze_core
  end
end
