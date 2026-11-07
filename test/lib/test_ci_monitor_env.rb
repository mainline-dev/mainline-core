# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'open3'

describe 'CI Monitor settings' do
  def github_settings
    %w[
      CI_MONITOR_GITHUB_APP_ID CI_MONITOR_GITHUB_APP_SLUG CI_MONITOR_GITHUB_APP_CLIENT_ID
      CI_MONITOR_GITHUB_APP_CLIENT_SECRET CI_MONITOR_GITHUB_PRIVATE_KEY CI_MONITOR_GITHUB_WEBHOOK_SECRET
    ]
  end

  def boot_app_without(var)
    Open3.capture2e({ 'RACK_ENV' => 'production', var => nil }, 'ruby', '-e', "require 'rack'; Rack::Builder.parse_file('config.ru')",
      chdir: File.expand_path('../..', __dir__))
  end

  it 'stops the app booting when any GitHub App setting is missing' do
    github_settings.each do |var|
      out, status = boot_app_without(var)

      refute_predicate status, :success?, "booted without #{var}"
      assert_includes out, var
    end
  end
end
