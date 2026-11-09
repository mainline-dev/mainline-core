# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/ci_monitor_dsl'

describe 'GitHub webhook' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    ENV['CI_MONITOR_GITHUB_WEBHOOK_SECRET'] = 'test-webhook-secret'
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(55555)
    @repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 55555,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main'
    )
  end

  def post_webhook(event:, payload:)
    body = JSON.generate(payload)
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'test-webhook-secret', body)}"
    post '/webhooks/github', body,
      'CONTENT_TYPE'             => 'application/json',
      'HTTP_X_GITHUB_EVENT'      => event,
      'HTTP_X_HUB_SIGNATURE_256' => signature
    last_response
  end

  it 'rejects invalid signature' do
    body = '{}'
    post '/webhooks/github', body,
      'CONTENT_TYPE'             => 'application/json',
      'HTTP_X_GITHUB_EVENT'      => 'create',
      'HTTP_X_HUB_SIGNATURE_256' => 'sha256=invalid'

    assert_equal 401, last_response.status
  end

  it 'creates tracked branch on branch create event' do
    response = post_webhook(
      event:   'create',
      payload: {
        ref_type:     'branch',
        ref:          'feature/login',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    assert_equal 200, response.status

    BypassRLS.call do
      branch = TrackedBranch.where(monitored_repo_id: @repo.id).first

      refute_nil branch
      assert_equal 'feature/login', branch.branch_name
      assert_equal 'open', branch.status
    end
  end

  it 'ignores tag create events' do
    response = post_webhook(
      event:   'create',
      payload: {
        ref_type:     'tag',
        ref:          'v1.0.0',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    assert_equal 200, response.status
    BypassRLS.call { assert_equal 0, TrackedBranch.where(monitored_repo_id: @repo.id).count }
  end

  it 'ignores default branch create' do
    response = post_webhook(
      event:   'create',
      payload: {
        ref_type:     'branch',
        ref:          'main',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    assert_equal 200, response.status
    BypassRLS.call { assert_equal 0, TrackedBranch.where(monitored_repo_id: @repo.id).count }
  end

  it 'marks branch abandoned on delete when no merged PR' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/old',
      status:            'open'
    )

    response = post_webhook(
      event:   'delete',
      payload: {
        ref_type:     'branch',
        ref:          'feature/old',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    assert_equal 200, response.status

    BypassRLS.call { branch.refresh }

    assert_equal 'abandoned', branch.status
    refute_nil branch.abandoned_at
  end

  it 'marks spiked branch abandoned on delete' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/experiment',
      status:            'spike'
    )

    post_webhook(
      event:   'delete',
      payload: {
        ref_type:     'branch',
        ref:          'spike/experiment',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    BypassRLS.call { branch.refresh }

    assert_equal 'abandoned', branch.status
  end

  it 'updates last_push_at on push to default branch' do
    response = post_webhook(
      event:   'push',
      payload: {
        ref:          'refs/heads/main',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    assert_equal 200, response.status

    BypassRLS.call { @repo.refresh }

    refute_nil @repo.last_push_at
  end

  it 'records integration event on push to default branch' do
    post_webhook(
      event:   'push',
      payload: {
        ref:          'refs/heads/main',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    BypassRLS.call do
      events = IntegrationEvent.where(monitored_repo_id: @repo.id).all

      assert_equal 1, events.size
      assert_equal 'push', events.first.event_type
    end
  end

  def push_to_main(sha:, at:)
    post_webhook(
      event:   'push',
      payload: {
        ref:          'refs/heads/main',
        after:        sha,
        head_commit:  { id: sha, timestamp: at },
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )
  end

  it 'counts a redelivered push once' do
    push_to_main(sha: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2', at: '2026-11-02T09:30:00+11:00')
    response = push_to_main(sha: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2', at: '2026-11-02T09:30:00+11:00')

    assert_equal 200, response.status
    BypassRLS.call { assert_equal 1, IntegrationEvent.where(monitored_repo_id: @repo.id, event_type: 'push').count }
  end

  it 'times a push from the commit it pushed' do
    push_to_main(sha: 'f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5', at: '2026-11-02T09:30:00+11:00')

    BypassRLS.call do
      assert_equal Time.parse('2026-11-02T09:30:00+11:00'), IntegrationEvent.where(monitored_repo_id: @repo.id).get(:occurred_at)
      assert_equal Time.parse('2026-11-02T09:30:00+11:00'), @repo.refresh.last_push_at
    end
  end

  it 'does not record integration event on push to non-default branch' do
    post_webhook(
      event:   'push',
      payload: {
        ref:          'refs/heads/feature/something',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    BypassRLS.call do
      assert_equal 0, IntegrationEvent.where(monitored_repo_id: @repo.id).count
    end
  end

  it 'ignores push to non-default branch' do
    response = post_webhook(
      event:   'push',
      payload: {
        ref:          'refs/heads/feature/something',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    assert_equal 200, response.status

    BypassRLS.call { @repo.refresh }

    assert_nil @repo.last_push_at
  end

  it 'ignores unknown installation' do
    response = post_webhook(
      event:   'create',
      payload: {
        ref_type:     'branch',
        ref:          'feature/x',
        installation: { id: 99999 },
        repository:   { id: 100 }
      }
    )

    assert_equal 200, response.status
    BypassRLS.call { assert_equal 0, TrackedBranch.count }
  end

  it 'ignores duplicate branch create events' do
    2.times do
      post_webhook(
        event:   'create',
        payload: {
          ref_type:     'branch',
          ref:          'feature/dup',
          installation: { id: 55555 },
          repository:   { id: 100 }
        }
      )
    end

    BypassRLS.call do
      branches = TrackedBranch.where(monitored_repo_id: @repo.id, status: 'open').all

      assert_equal 1, branches.size
    end
  end

  it 'does not duplicate a spiked branch on create event' do
    BypassRLS.call do
      TrackedBranch.create(
        monitored_repo_id: @repo.id,
        branch_name:       'spike/experiment',
        status:            'spike'
      )
    end

    post_webhook(
      event:   'create',
      payload: {
        ref_type:     'branch',
        ref:          'spike/experiment',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    BypassRLS.call do
      all = TrackedBranch.where(monitored_repo_id: @repo.id).all

      assert_equal 1, all.size
      assert_equal 'spike', all.first.status
    end
  end

  it 'handles all matching repos for multi-team installations' do
    team_b = Team.create(name: 'Team B')
    repo_b = BypassRLS.call {
      MonitoredRepo.create(
        team_id:                  team_b.id,
        provider_installation_id: 55555,
        provider_repo_id:         100,
        repo_name:                'acme/webapp',
        default_branch:           'main'
      )
    }

    post_webhook(
      event:   'create',
      payload: {
        ref_type:     'branch',
        ref:          'feature/shared',
        installation: { id: 55555 },
        repository:   { id: 100 }
      }
    )

    BypassRLS.call do
      branch_a = TrackedBranch.where(monitored_repo_id: @repo.id).first
      branch_b = TrackedBranch.where(monitored_repo_id: repo_b.id).first

      refute_nil branch_a
      refute_nil branch_b
      assert_equal 'feature/shared', branch_a.branch_name
      assert_equal 'feature/shared', branch_b.branch_name
    end
  end

  it 'updates repo name when repository is renamed' do
    post_webhook(
      event:   'push',
      payload: {
        ref:          'refs/heads/main',
        installation: { id: 55555 },
        repository:   { id: 100, full_name: 'acme/webapp-renamed' }
      }
    )

    SetTeamContext.call(@team.id)
    repo = MonitoredRepo[@repo.id]

    assert_equal 'acme/webapp-renamed', repo.repo_name
  end

  it 'ignores installation created event' do
    post_webhook(
      event:   'installation',
      payload: {
        action:       'created',
        installation: { id: 55555, account: { login: 'acme' } },
        repositories: [
          { id: 200, full_name: 'acme/api', default_branch: 'main' }
        ]
      }
    )

    repos = BypassRLS.call { MonitoredRepo.where(team_id: @team.id).all }

    assert_equal 1, repos.size
  end

  it 'cleans up repos and branches when installation is deleted' do
    BypassRLS.call do
      TrackedBranch.create(
        monitored_repo_id: @repo.id, branch_name: 'feature/wip', status: 'open'
      )
    end

    post_webhook(
      event:   'installation',
      payload: {
        action:       'deleted',
        installation: { id: 55555, account: { login: 'acme' } }
      }
    )

    BypassRLS.call do
      assert_equal 0, TrackedBranch.where(monitored_repo_id: @repo.id).count
      assert_equal 0, MonitoredRepo.where(provider_installation_id: 55555).count
      assert_equal 0, TeamInstallation.where(installation_id: 55555).count
    end
  end

  it 'cleans up repos and branches when installation is suspended' do
    post_webhook(
      event:   'installation',
      payload: {
        action:       'suspended',
        installation: { id: 55555, account: { login: 'acme' } }
      }
    )

    BypassRLS.call do
      assert_equal 0, MonitoredRepo.where(provider_installation_id: 55555).count
      assert_equal 0, TeamInstallation.where(installation_id: 55555).count
    end
  end

  it 'ignores installation_repositories event' do
    post_webhook(
      event:   'installation_repositories',
      payload: {
        action:             'added',
        installation:       { id: 55555 },
        repositories_added: [
          { id: 400, full_name: 'acme/new-service', default_branch: 'main' }
        ]
      }
    )

    repos = BypassRLS.call { MonitoredRepo.where(team_id: @team.id).all }

    assert_equal 1, repos.size
  end

  it 'marks branch merged on pull_request closed+merged' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/login',
      status:            'open'
    )

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'closed',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: true, head: { ref: 'feature/login' } }
      }
    )

    BypassRLS.call { branch.refresh }

    assert_equal 'merged', branch.status
    refute_nil branch.merged_at
  end

  it 'uses payload merged_at for branch and event timestamps' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/timestamped',
      status:            'open'
    )
    merged_time = '2026-05-20T14:30:00Z'

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'closed',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: true, merged_at: merged_time, head: { ref: 'feature/timestamped' } }
      }
    )

    BypassRLS.call do
      branch.refresh

      assert_equal Time.parse(merged_time).utc.to_i, branch.merged_at.utc.to_i

      event = IntegrationEvent.where(monitored_repo_id: @repo.id, event_type: 'merge').first

      assert_equal Time.parse(merged_time).utc.to_i, event.occurred_at.utc.to_i
    end
  end

  it 'records integration event on pull_request merged' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/tracked',
      status:            'open'
    )

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'closed',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: true, head: { ref: 'feature/tracked' } }
      }
    )

    BypassRLS.call do
      events = IntegrationEvent.where(monitored_repo_id: @repo.id).all

      assert_equal 1, events.size
      assert_equal 'merge', events.first.event_type
      assert_equal branch.id, events.first.tracked_branch_id
    end
  end

  it 'marks spiked branch merged on pull_request closed+merged' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/experiment',
      status:            'spike'
    )

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'closed',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: true, head: { ref: 'spike/experiment' } }
      }
    )

    BypassRLS.call { branch.refresh }

    assert_equal 'merged', branch.status
  end

  it 'flags merged_from_spike when spiked branch is merged' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/sneaky',
      status:            'spike'
    )

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'closed',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: true, head: { ref: 'spike/sneaky' } }
      }
    )

    BypassRLS.call { branch.refresh }

    assert_equal 'merged', branch.status
    assert branch.merged_from_spike, 'should flag that this was merged from spike status'
  end

  it 'marks abandoned branch merged when PR merge arrives late' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/race',
      status:            'abandoned',
      abandoned_at:      Time.now
    )

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'closed',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: true, head: { ref: 'feature/race' } }
      }
    )

    BypassRLS.call { branch.refresh }

    assert_equal 'merged', branch.status
    refute_nil branch.merged_at
  end

  it 'ignores pull_request closed without merge' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/abandoned',
      status:            'open'
    )

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'closed',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: false, head: { ref: 'feature/abandoned' } }
      }
    )

    BypassRLS.call { branch.refresh }

    assert_equal 'open', branch.status
  end

  it 'ignores pull_request opened event' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/wip',
      status:            'open'
    )

    post_webhook(
      event:   'pull_request',
      payload: {
        action:       'opened',
        installation: { id: 55555 },
        repository:   { id: 100 },
        pull_request: { merged: false, head: { ref: 'feature/wip' } }
      }
    )

    BypassRLS.call do
      branch = TrackedBranch.where(monitored_repo_id: @repo.id).first

      assert_equal 'open', branch.status
    end
  end
end
