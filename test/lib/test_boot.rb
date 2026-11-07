# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../subprocess_helper'

describe 'Booting with the database settings' do
  # The test database, handed over under the names a hosted deploy uses.
  def test_database_as_hosted
    {
      'MAINLINE_DATABASE_URL'     => ENV.fetch('TEST_DATABASE_URL'),
      'MAINLINE_APP_DATABASE_URL' => ENV.fetch('TEST_APP_DATABASE_URL')
    }
  end

  def boot_web(env)
    script = %q(require 'rack'; Rack::Builder.parse_file('config.ru'); puts "DB_USER:#{DB.get(Sequel.lit('current_user'))}")
    Subprocess.run({ 'RACK_ENV' => 'production' }.merge(env), 'ruby', '-e', script)
  end

  def boot_worker(env)
    Subprocess.run({ 'RACK_ENV' => 'production' }.merge(env), 'ruby', '-e', "require './sidekiq_boot'")
  end

  def connect(env)
    script = %q(puts "DB_USER:#{DB.get(Sequel.lit('current_user'))}")
    Subprocess.run(env, 'ruby', '-r', './db', '-e', script)
  end

  %w[MAINLINE_DATABASE_URL MAINLINE_APP_DATABASE_URL].each do |var|
    it "refuses to start the web app without #{var}" do
      out, status = boot_web(var => nil)

      refute_predicate status, :success?
      assert_includes out, "FATAL: required environment variable #{var}"
    end

    it "refuses to start the worker without #{var}" do
      out, status = boot_worker(var => nil)

      refute_predicate status, :success?
      assert_includes out, "FATAL: required environment variable #{var}"
    end
  end

  it 'connects the web app as the restricted app role, not the database owner' do
    out, status = boot_web(test_database_as_hosted)

    assert_predicate status, :success?, out
    assert_equal 'mainline_app', out[/^DB_USER:(.*)$/, 1]
  end

  it 'connects as the restricted app role in test mode too' do
    out, status = connect({ 'RACK_ENV' => 'test' })

    assert_predicate status, :success?, out
    assert_equal 'mainline_app', out[/^DB_USER:(.*)$/, 1]
  end

  { 'test' => 'TEST_APP_DATABASE_URL', 'development' => 'MAINLINE_APP_DATABASE_URL' }.each do |mode, var|
    it "names the missing database variable in #{mode} mode" do
      out, status = connect({ 'RACK_ENV' => mode, var => nil })

      refute_predicate status, :success?
      assert_includes out, "FATAL: required environment variable #{var}"
    end
  end

  it 'has no sign-in route for a provider whose client id is disabled' do
    script = %q(require './app'; require 'rack/mock'; puts "STATUS:#{Rack::MockRequest.new(Mainline.app).post('/auth/gitlab').status}")
    out, status = Subprocess.run({ 'RACK_ENV' => 'test', 'GITLAB_CLIENT_ID' => 'disabled' }, 'ruby', '-e', script)

    assert_predicate status, :success?, out
    assert_equal '404', out[/^STATUS:(\d+)/, 1]
  end
end
