# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../subprocess_helper'

describe 'sidekiq boot file' do
  def job_classes_loaded_by(file)
    script = <<~'RUBY'
      require "./#{ARGV[0]}"
      jobs = ObjectSpace.each_object(Class).select { |c| c.ancestors.include?(Sidekiq::Job) && c.name }
      puts "JOBS:#{jobs.map(&:name).sort.join(',')}"
    RUBY
    out, status = Subprocess.run({ 'RACK_ENV' => 'test' }, 'ruby', '-e', script, file)

    assert_predicate status, :success?, out
    out[/^JOBS:(.*)$/, 1].split(',')
  end

  # Each listener as its event and the line that subscribed it.
  def event_listeners_loaded_by(file)
    script = <<~'RUBY'
      require "./#{ARGV[0]}"
      listeners = CoreEvents.instance_variable_get(:@subscriptions).map { |sub| "#{sub.event}@#{sub.block.source_location.join(':')}" }
      puts "LISTENERS:#{listeners.sort.join(',')}"
    RUBY
    out, status = Subprocess.run({ 'RACK_ENV' => 'test' }, 'ruby', '-e', script, file)

    assert_predicate status, :success?, out
    out[/^LISTENERS:(.*)$/, 1].split(',')
  end

  it 'refuses to start a worker without a required variable' do
    out, status = Subprocess.run({ 'RACK_ENV' => 'test', 'SMTP_HOST' => nil }, 'ruby', '-e', "require './sidekiq_boot'")

    refute_predicate status, :success?
    assert_includes out, 'FATAL: required environment variable SMTP_HOST'
  end

  it 'boots a worker that can run every job the web app can enqueue' do
    app_jobs = job_classes_loaded_by('app')
    worker_jobs = job_classes_loaded_by('sidekiq_boot')

    refute_empty app_jobs
    assert_empty app_jobs - worker_jobs, 'the worker cannot run these jobs'
  end

  it 'boots a worker that hears every event the web app listens for' do
    app_listeners = event_listeners_loaded_by('app')
    worker_listeners = event_listeners_loaded_by('sidekiq_boot')

    assert_empty app_listeners - worker_listeners, 'the worker misses these listeners'
  end
end
