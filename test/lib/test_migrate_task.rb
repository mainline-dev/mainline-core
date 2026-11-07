# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../subprocess_helper'

describe 'rake test_up' do
  it 'refuses to migrate without the test database owner URL' do
    out, status = Subprocess.run({ 'TEST_DATABASE_URL' => nil }, 'rake', 'test_up')

    refute_predicate status, :success?
    assert_includes out, 'FATAL: required environment variable TEST_DATABASE_URL'
  end

  it 'applies nothing when run again' do
    out, status = Subprocess.run({}, 'rake', 'test_up')

    assert_predicate status, :success?, out
    refute_includes out, 'Begin applying migration'
  end
end
