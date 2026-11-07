# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'yaml'
require_relative '../../lib/env_requirements'

# Self-hosting runs docker-compose.selfhost.yml with the variables the README
# lists. These fail when the compose file, the README or the app's list of
# required variables drift apart.
describe 'Self-host setup' do
  def root
    File.expand_path('../..', __dir__)
  end

  def compose
    YAML.safe_load_file(File.join(root, 'docker-compose.selfhost.yml'), aliases: true)
  end

  # The variables the compose file asks the person running it for.
  def asked_for
    File.read(File.join(root, 'docker-compose.selfhost.yml')).scan(/\$\{([A-Z0-9_]+):\?/).flatten.uniq.sort
  end

  def readme_table
    File.read(File.join(root, 'README.md')).scan(/^\| `([A-Z0-9_]+)`/).flatten.uniq.sort
  end

  %w[app worker].each do |service|
    it "gives the #{service} every variable core requires" do
      env = compose.dig('services', service, 'environment').keys

      assert_empty EnvRequirements::CORE.keys - env
    end

    # The README's quick start runs docker-compose.yml, and a service missing a
    # required variable refuses to boot.
    it "gives the development #{service} every variable the app requires" do
      development = YAML.safe_load_file(File.join(root, 'docker-compose.yml'), aliases: true)
      env = development.dig('services', service, 'environment').keys

      assert_empty EnvRequirements.required.keys - env
    end
  end

  # The app runs the migrations as it starts; a worker started earlier would
  # boot against a database that is not ready.
  it 'starts the worker once the app answers its health check' do
    services = compose['services']

    assert_includes services.dig('app', 'healthcheck', 'test').join(' '), '/up'
    assert_equal 'service_healthy', services.dig('worker', 'depends_on', 'app', 'condition')
  end

  it 'lists in the README exactly the variables the compose file asks for' do
    assert_equal asked_for, readme_table
  end
end
