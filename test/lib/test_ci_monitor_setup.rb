# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require_relative '../../lib/ci_monitor_setup'

describe CIMonitorSetup do
  cover 'CIMonitorSetup*'

  def settings(value)
    CIMonitorSetup::SETTINGS.to_h { |name| [name, value] }
  end

  it 'is on when its settings hold a GitHub App' do
    assert CIMonitorSetup.on?(settings('12345'))
  end

  it 'is off when every setting is disabled' do
    refute CIMonitorSetup.on?(settings('disabled'))
  end

  it 'has six settings, one for each part of the GitHub App' do
    assert_equal %w[
      CI_MONITOR_GITHUB_APP_ID CI_MONITOR_GITHUB_APP_SLUG CI_MONITOR_GITHUB_APP_CLIENT_ID
      CI_MONITOR_GITHUB_APP_CLIENT_SECRET CI_MONITOR_GITHUB_PRIVATE_KEY CI_MONITOR_GITHUB_WEBHOOK_SECRET
    ], CIMonitorSetup::SETTINGS
  end

  it 'names the settings still set when only some are disabled' do
    env = settings('12345').merge('CI_MONITOR_GITHUB_APP_ID' => 'disabled', 'CI_MONITOR_GITHUB_APP_SLUG' => 'disabled')

    assert_equal CIMonitorSetup::SETTINGS - %w[CI_MONITOR_GITHUB_APP_ID CI_MONITOR_GITHUB_APP_SLUG],
      CIMonitorSetup.half_off(env)
  end

  it 'counts a setting that is not there as set, leaving the start-up check to report it missing' do
    assert CIMonitorSetup.on?({})
    assert_empty CIMonitorSetup.half_off({})
  end

  it "reads this process's environment unless told otherwise" do
    was = CIMonitorSetup::SETTINGS.to_h { |name| [name, ENV.fetch(name, nil)] }
    CIMonitorSetup::SETTINGS.each { |name| ENV[name] = 'disabled' }
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'

    refute_predicate CIMonitorSetup, :on?
    assert_equal ['CI_MONITOR_GITHUB_APP_ID'], CIMonitorSetup.half_off
  ensure
    was.each { |name, value| ENV[name] = value }
  end

  it 'names nothing when every setting is disabled, or none is' do
    assert_empty CIMonitorSetup.half_off(settings('disabled'))
    assert_empty CIMonitorSetup.half_off(settings('12345'))
  end
end
