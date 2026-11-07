# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../subprocess_helper'

describe 'Sentry environment' do
  it 'labels error reports with SENTRY_ENVIRONMENT' do
    script = %q(require './app'; puts "SENTRY_ENV:#{Sentry.configuration.environment}")
    out, status = Subprocess.run({ 'RACK_ENV' => 'test', 'SENTRY_ENVIRONMENT' => 'staging' }, 'ruby', '-e', script)

    assert_predicate status, :success?, out
    assert_equal 'staging', out[/^SENTRY_ENV:(.*)$/, 1]
  end
end
