# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/ci_monitor_dsl'

# Anyone can send a request, so a body too large to be anything the app takes
# is turned away before any route reads it.
describe 'Request size' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    ENV['CI_MONITOR_GITHUB_WEBHOOK_SECRET'] = 'test-webhook-secret'
    setup_team
    add_person(name: 'Alice')
    connect_github_installation(55555)
    @repo = MonitoredRepo.create(team_id: @team.id, provider_installation_id: 55555, provider_repo_id: 100,
      repo_name: 'acme/webapp', default_branch: 'main')
  end

  # A branch-created event, padded past the limit and signed properly, so only
  # its size can turn it away.
  def oversized_branch_event
    payload = { ref_type: 'branch', ref: 'feature/huge', installation: { id: 55555 }, repository: { id: 100 },
                padding: 'x' * RequestSizeLimit::MAX_BYTES }
    body = JSON.generate(payload)
    [body, "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'test-webhook-secret', body)}"]
  end

  def tracked_branches
    BypassRLS.call { TrackedBranch.where(monitored_repo_id: @repo.id).count }
  end

  it 'turns away a webhook over the limit before reading it' do
    body, signature = oversized_branch_event

    post '/webhooks/github', body,
      'CONTENT_TYPE' => 'application/json', 'HTTP_X_GITHUB_EVENT' => 'create', 'HTTP_X_HUB_SIGNATURE_256' => signature

    assert_equal 413, last_response.status
    assert_equal 0, tracked_branches
  end

  it 'turns away a body of unknown length once it passes the limit' do
    body, signature = oversized_branch_event
    env = Rack::MockRequest.env_for('/webhooks/github', method: 'POST', input: body,
      'CONTENT_TYPE' => 'application/json', 'HTTP_X_GITHUB_EVENT' => 'create', 'HTTP_X_HUB_SIGNATURE_256' => signature)
    env.delete('CONTENT_LENGTH')

    status, = app.call(env)

    assert_equal 413, status
    assert_equal 0, tracked_branches
  end

  it 'takes a body of unknown length under the limit' do
    body = JSON.generate(ref_type: 'branch', ref: 'feature/small', installation: { id: 55555 }, repository: { id: 100 })
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'test-webhook-secret', body)}"
    env = Rack::MockRequest.env_for('/webhooks/github', method: 'POST', input: body,
      'CONTENT_TYPE' => 'application/json', 'HTTP_X_GITHUB_EVENT' => 'create', 'HTTP_X_HUB_SIGNATURE_256' => signature)
    env.delete('CONTENT_LENGTH')

    status, = app.call(env)

    assert_equal 200, status
    assert_equal 1, tracked_branches
  end
end
