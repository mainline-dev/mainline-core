# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'uri'
require_relative '../subprocess_helper'

describe 'rake prod_up' do
  # An owner URL with a password that must never be printed, pointing at a
  # database that does not exist so the migration is sure to fail.
  def bogus_owner_url
    uri = URI.parse(ENV.fetch('TEST_DATABASE_URL'))
    uri.password = 'sekrit'
    uri.path = '/no_such_database'
    uri.to_s
  end

  it 'refuses to migrate when a required variable is missing' do
    env = { 'SMTP_HOST' => nil, 'MAINLINE_DATABASE_URL' => ENV.fetch('TEST_DATABASE_URL') }
    out, status = Subprocess.run(env, 'rake', 'prod_up')

    refute_predicate status, :success?
    assert_includes out, 'FATAL: required environment variable SMTP_HOST'
    refute_includes out, 'schema_info', 'migrations ran before the environment check'
  end

  it 'refuses to migrate without the database owner URL' do
    out, status = Subprocess.run({ 'MAINLINE_DATABASE_URL' => nil }, 'rake', 'prod_up')

    refute_predicate status, :success?
    assert_includes out, 'FATAL: required environment variable MAINLINE_DATABASE_URL'
  end

  it 'does not print the database password when a migration fails' do
    out, status = Subprocess.run({ 'MAINLINE_DATABASE_URL' => bogus_owner_url }, 'rake', '--trace', 'prod_up')

    refute_predicate status, :success?
    refute_includes out, 'sekrit'
  end
end
