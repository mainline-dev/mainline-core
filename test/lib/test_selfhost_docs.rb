# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'yaml'
require_relative '../../lib/env_requirements'

# Self-hosting runs docker-compose.selfhost.yml with the variables the README
# lists; the quick start's docker-compose.yml is a trial of the published
# image; contributors run docker-compose.dev.yml. These fail when the compose
# files, the README or the app's list of required variables drift apart.
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

  def trial
    YAML.safe_load_file(File.join(root, 'docker-compose.yml'), aliases: true)
  end

  def development
    YAML.safe_load_file(File.join(root, 'docker-compose.dev.yml'), aliases: true)
  end

  def published_image
    workflow = YAML.load_file(File.join(root, '.github/workflows/publish_image.yml'))
    workflow.dig('jobs', 'image', 'steps').filter_map { |step| step.dig('with', 'images') }.first
  end

  def readme_table
    File.read(File.join(root, 'README.md')).scan(/^\| `([A-Z0-9_]+)`/).flatten.uniq.sort
  end

  %w[app worker].each do |service|
    # Self-hosting pulls the image the public repository publishes, so nobody
    # has to build. Building from the checkout stays possible with --build.
    it "runs the #{service} from the published image, or from the checkout when asked to build" do
      assert_equal "#{published_image}:latest", compose.dig('services', service, 'image')
      assert_equal '.', compose.dig('services', service, 'build')
    end

    # The quick start is a trial: nothing is built on the person's machine.
    it "runs the trial #{service} from the published image, building nothing" do
      assert_equal "#{published_image}:latest", trial.dig('services', service, 'image')
      assert_nil trial.dig('services', service, 'build')
    end

    it "gives the trial #{service} every variable core requires" do
      env = trial.dig('services', service, 'environment').keys

      assert_empty EnvRequirements::CORE.keys - env
    end

    it "gives the #{service} every variable core requires" do
      env = compose.dig('services', service, 'environment').keys

      assert_empty EnvRequirements::CORE.keys - env
    end

    # A service missing a required variable refuses to boot.
    it "gives the development #{service} every variable the app requires" do
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

  # On a fresh start the app runs the migrations, so a worker started before
  # it finds no tables and exits. The trial and the development stack alike.
  { 'trial' => 'docker-compose.yml', 'development' => 'docker-compose.dev.yml' }.each do |name, file|
    it "starts the #{name} worker once the app answers its health check too" do
      services = YAML.safe_load_file(File.join(root, file), aliases: true)['services']

      assert_includes services.dig('app', 'healthcheck', 'test').join(' '), '/up'
      assert_equal 'service_healthy', services.dig('worker', 'depends_on', 'app', 'condition')
    end
  end

  it 'publishes only the trial app, and only on this machine' do
    published = trial['services'].transform_values { |service| service['ports'] }.compact

    assert_equal({ 'app' => ['127.0.0.1:3000:3000'] }, published)
  end

  it 'seeds the trial on its first start and prints the login links' do
    assert_includes trial.dig('services', 'app', 'command').to_s, 'rake trial_up'
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
