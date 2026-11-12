# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'yaml'

# Every layer of tests that runs before a push from a developer's machine also
# runs in CI, so a pull request is held to what a local push is. These fail
# when CI and the local script stop running the same things.
describe 'CI runs every test layer' do
  def root
    File.expand_path('../..', __dir__)
  end

  def ci_commands
    jobs = YAML.load_file(File.join(root, '.github/workflows/ci.yml'))['jobs']
    jobs.values.flat_map { |job| job.fetch('steps', []).filter_map { |step| step['run'] } }
  end

  def local_script
    File.read(File.join(root, 'scripts/test.sh'))
  end

  it 'runs the browser tests in CI with the script the local run uses' do
    assert_includes ci_commands, './scripts/browser_test.sh'
    assert_includes local_script, 'scripts/browser_test.sh'
    assert_path_exists File.join(root, 'scripts/browser_test.sh')
  end

  # Mutation testing is not a CI gate. The local run shows what survives in
  # the classes a change touched, and stops a class getting worse.
  it 'mutation-tests the changed classes in the local run' do
    assert_includes local_script, 'rake mutant_changed'
  end

  it 'runs lint, model and acceptance tests in CI' do
    assert_includes ci_commands, './scripts/ci_test.sh'
  end
end
