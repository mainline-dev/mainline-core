# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'yaml'

# The public repository publishes a container image for each version. The
# workflow file is also in the hosted repository, which the public one is
# exported from, so these fail if a tag there could publish hosted code under
# the public name.
describe 'Publishing the image' do
  def workflow
    YAML.load_file(File.expand_path('../../.github/workflows/publish_image.yml', __dir__))
  end

  def job
    workflow.dig('jobs', 'image')
  end

  def step(action)
    job['steps'].find { |step| step['uses'].to_s.start_with?("#{action}@") }
  end

  # YAML reads a bare "on" as true.
  it 'publishes when a version tag is pushed, and at no other time' do
    assert_equal({ 'push' => { 'tags' => ['v*'] } }, workflow[true])
  end

  it 'publishes only from the public repository' do
    assert_equal "github.repository == 'mainline-dev/mainline-core'", job['if']
  end

  it 'names the image after the public repository' do
    assert_equal 'ghcr.io/mainline-dev/mainline-core', step('docker/metadata-action').dig('with', 'images')
  end

  it 'builds for Intel and ARM machines' do
    assert_equal 'linux/amd64,linux/arm64', step('docker/build-push-action').dig('with', 'platforms')
  end
end
