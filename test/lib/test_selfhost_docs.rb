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

  # The quick start's stack: on a fresh clone the app runs the migrations, so
  # a worker started before it finds no tables and exits.
  it 'starts the quick start worker once the app answers its health check too' do
    services = YAML.safe_load_file(File.join(root, 'docker-compose.yml'), aliases: true)['services']

    assert_includes services.dig('app', 'healthcheck', 'test').join(' '), '/up'
    assert_equal 'service_healthy', services.dig('worker', 'depends_on', 'app', 'condition')
  end

  it 'publishes the app only to the local proxy, not to the internet' do
    assert_equal ['127.0.0.1:3000:3000'], compose.dig('services', 'app', 'ports')
  end

  it 'keeps the .env file the README suggests out of git and out of the image' do
    ignored = File.readlines(File.join(root, '.gitignore'), chomp: true)
    not_in_image = File.readlines(File.join(root, '.dockerignore'), chomp: true)

    assert_includes ignored, '/.env'
    assert_empty %w[.env .env.* .git] - not_in_image
  end

  it 'changes into the folder the quick start clone creates' do
    readme = File.read(File.join(root, 'README.md'))
    cloned = readme[%r{git clone \S+/([^/\s]+)\.git}, 1]

    assert_includes readme, "cd #{cloned}\n"
  end

  it 'builds pull requests as well as pushes to master' do
    triggers = YAML.safe_load_file(File.join(root, '.github/workflows/ci.yml'), aliases: true)[true]

    assert_includes triggers.keys, 'pull_request'
    assert_includes triggers.keys, 'push'
  end

  it 'lists in the README exactly the variables the compose file asks for' do
    assert_equal asked_for, readme_table
  end
end
