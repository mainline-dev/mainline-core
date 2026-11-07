# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/ci_monitor_dsl'

describe 'CI Monitor' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'returns 404 for a non-UUID branch id' do
    err = assert_raises(RuntimeError) { driver.post "/teams/#{@team.id}/monitor/branches/b3404700/spike" }

    assert_match(/404/, err.message)
  end

  it 'returns 404 for a non-UUID repo id' do
    err = assert_raises(RuntimeError) { driver.post "/teams/#{@team.id}/monitor/repos/b3404700/remove" }

    assert_match(/404/, err.message)
  end

  it 'shows empty state when GitHub is not connected' do
    visit_monitor(@team)

    body = page_body

    assert_shown('monitor-connect', body)
  end

  it 'shows monitor dashboard when GitHub is connected' do
    connect_github_installation(12345)

    visit_monitor(@team)

    body = page_body

    refute_shown('monitor-connect', body)
  end

  it 'lets dashboard errors propagate instead of masking them' do
    connect_github_installation(12345)
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main'
    )
    TrackedBranch.create(
      monitored_repo_id: repo.id,
      branch_name:       'feature/x',
      status:            'open'
    )

    assert_raises(RuntimeError) do
      CIMonitor::BranchAge.stub(:hours, ->(*) { raise 'boom' }) do
        visit_monitor(@team)
      end
    end
  end
end

describe 'CI Monitor - GitHub App installation' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    ENV['CI_MONITOR_GITHUB_APP_SLUG'] = 'mainline-ci-monitor'
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_ID'] = 'test-client-id'
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_SECRET'] = 'test-client-secret'
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'install redirects to GitHub App OAuth when no token in session' do
    response = visit_monitor_install(@team)

    assert_equal 302, response.status
    assert_includes response['Location'], 'github.com/login/oauth/authorize'
    assert_includes response['Location'], 'client_id=test-client-id'
  end

  it 'install redirect includes a signed state parameter' do
    response = visit_monitor_install(@team)

    location = response['Location']
    state_match = location.match(/state=([^&]+)/)

    refute_nil state_match, 'redirect URL must include state param'
    state_value = Rack::Utils.unescape(state_match[1])
    verified = SignedState.verify(state_value)

    assert_equal @team.id, verified
  end

  it 'oauth callback rejects missing state' do
    response = visit_monitor_oauth_callback(@team, code: 'test-code', state: nil, stub_token: 'ghu_token')

    assert_equal 302, response.status
    assert_includes response['Location'], "/teams/#{@team.id}/monitor"
    refute_includes response['Location'], 'install'
  end

  it 'oauth callback rejects tampered state' do
    response = visit_monitor_oauth_callback(@team, code: 'test-code', state: 'forged.garbage', stub_token: 'ghu_token')

    assert_equal 302, response.status
    assert_includes response['Location'], "/teams/#{@team.id}/monitor"
    refute_includes response['Location'], 'install'
  end

  it 'install redirects to OAuth when token is expired by API error' do
    stub_error = ->(_token) { raise CIMonitor::GithubAPI::Error, 'forbidden' }
    CIMonitor::GithubAPI.stub(:user_installations, stub_error) do
      driver.post '/_test_login', { 'person_id' => @alice.id, 'ci_monitor_token' => 'expired-token' }
      driver.get "/teams/#{@team.id}/monitor/install"
    end

    response = driver.last_response

    assert_equal 302, response.status
    assert_includes response['Location'], 'github.com/login/oauth/authorize'
  end

  it 'install redirects to OAuth when token is older than one hour' do
    app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
    stub_installations = [{ app_id: app_id, id: 99999, account_login: 'acme' }]
    CIMonitor::GithubAPI.stub(:user_installations, ->(_token) { stub_installations }) do
      params = { 'person_id' => @alice.id, 'ci_monitor_token' => 'stale-token',
                 'ci_monitor_token_at' => (Time.now - 3601).to_i.to_s }
      driver.post '/_test_login', params
      driver.get "/teams/#{@team.id}/monitor/install"
    end

    response = driver.last_response

    assert_equal 302, response.status
    assert_includes response['Location'], 'github.com/login/oauth/authorize'
  end

  it 'install shows picker with valid token' do
    app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
    stub_installations = [{ app_id: app_id, id: 77777, account_login: 'acme' }]
    response = visit_monitor_install(
      @team,
      ci_monitor_token:        'valid-token',
      stub_user_installations: stub_installations
    )

    assert_equal 200, response.status
    assert_includes page_body, 'acme'
    assert_includes page_body, 'installation-picker'
  end

  it 'install shows picker when multiple unlinked installations exist' do
    app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
    stub_installations = [
      { app_id: app_id, id: 77777, account_login: 'acme' },
      { app_id: app_id, id: 88888, account_login: 'acme-labs' }
    ]
    response = visit_monitor_install(
      @team,
      ci_monitor_token:        'valid-token',
      stub_user_installations: stub_installations
    )

    assert_equal 200, response.status
    assert_includes response.body, 'acme'
    assert_includes response.body, 'acme-labs'
    assert_includes response.body, 'data-test-id="installation-picker"'
  end

  it 'install skips already-linked installations in picker' do
    app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
    connect_github_installation(77777)
    stub_installations = [
      { app_id: app_id, id: 77777, account_login: 'acme' },
      { app_id: app_id, id: 88888, account_login: 'acme-labs' }
    ]
    response = visit_monitor_install(
      @team,
      ci_monitor_token:        'valid-token',
      stub_user_installations: stub_installations
    )

    assert_equal 200, response.status
    assert_includes page_body, 'acme-labs'
    refute_includes page_body, 'value="77777"'
  end

  it 'install shows install-more link when all installations already linked' do
    app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
    connect_github_installation(77777)
    stub_installations = [{ app_id: app_id, id: 77777, account_login: 'acme' }]
    response = visit_monitor_install(
      @team,
      ci_monitor_token:        'valid-token',
      stub_user_installations: stub_installations
    )

    assert_equal 200, response.status
    assert_includes page_body, 'github.com/apps/mainline-ci-monitor'
  end

  it 'install cleans up stale TeamInstallation when app uninstalled from GitHub' do
    connect_github_installation(77777)

    assert_equal 1, TeamInstallation.where(team_id: @team.id).count

    stub_installations = []
    response = visit_monitor_install(
      @team,
      ci_monitor_token:        'valid-token',
      stub_user_installations: stub_installations
    )

    assert_equal 302, response.status
    assert_includes response['Location'], "/teams/#{@team.id}/monitor"
    refute_includes response['Location'], 'install'
    assert_equal 0, TeamInstallation.where(team_id: @team.id).count
  end

  it 'install redirects to dashboard when no matching app installation' do
    stub_installations = [{ app_id: 99999, id: 77777, account_login: 'other' }]
    response = visit_monitor_install(
      @team,
      ci_monitor_token:        'valid-token',
      stub_user_installations: stub_installations
    )

    assert_equal 302, response.status
    assert_includes response['Location'], "/teams/#{@team.id}/monitor"
    refute_includes response['Location'], 'install'
  end

  it 'oauth callback exchanges code for token and redirects to install' do
    state = SignedState.generate(@team.id)
    response = visit_monitor_oauth_callback(@team, code: 'test-code', state: state, stub_token: 'ghu_new_token')

    assert_equal 302, response.status
    assert_includes response['Location'], "/teams/#{@team.id}/monitor/install"
  end
end

describe 'CI Monitor - GitHub App callback (top-level)' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'stores installation_id with org_name and redirects to monitor' do
    stub_account = ->(_id) { 'acme-corp' }
    response = CIMonitor::GithubAPI.stub(:installation_account, stub_account) {
      github_app_callback(installation_id: 99999, state: @team.id)
    }

    ti = TeamInstallation.where(team_id: @team.id, installation_id: 99999).first

    refute_nil ti
    assert_equal 'acme-corp', ti.org_name
    assert_equal 302, response.status
    assert_includes response['Location'], "/teams/#{@team.id}/monitor"
  end

  it 'does not duplicate existing installation' do
    connect_github_installation(11111)

    github_app_callback(installation_id: 11111, state: @team.id)

    assert_equal 1, TeamInstallation.where(team_id: @team.id, installation_id: 11111).count
  end

  it 'rejects missing installation_id' do
    github_app_callback(installation_id: nil, state: @team.id)

    assert_equal 0, TeamInstallation.where(team_id: @team.id).count
  end

  it 'rejects invalid team in state param' do
    response = github_app_callback(installation_id: 99999, state: '00000000-0000-0000-0000-000000000000')

    assert_equal 302, response.status
    assert_includes response['Location'], '/teams'
  end

  it 'rejects tampered state signature' do
    response = github_app_callback(installation_id: 99999, state: @team.id, sign: false)

    assert_equal 302, response.status
    assert_includes response['Location'], '/teams'
  end

  it 'falls back to session team_id when GitHub drops state param' do
    ENV['CI_MONITOR_GITHUB_APP_SLUG'] = 'test-app'
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_ID'] = 'test-client-id'
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_SECRET'] = 'test-client-secret'
    visit_monitor_install(@team)

    response = CIMonitor::GithubAPI.stub(:installation_account, nil) {
      github_app_callback(installation_id: 99999, state: nil)
    }

    ti = TeamInstallation.where(team_id: @team.id, installation_id: 99999).first

    refute_nil ti
    assert_equal 302, response.status
    assert_includes response['Location'], "/teams/#{@team.id}/monitor"
  end
end

describe 'CI Monitor - dashboard status' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
    @repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      last_push_at:             Time.now,
      threshold_hours:          24
    )
  end

  it 'shows summary with zero open branches when green' do
    visit_monitor(@team)

    body = page_body

    assert_open_branches(body, 0)
    assert_includes body, 'data-test-id="monitor-summary"'
  end

  it 'shows add repos link on dashboard' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="add-repos"'
    assert_includes body, "/teams/#{@team.id}/monitor/select-repos"
  end

  it 'shows connect another org link on dashboard' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="connect-org"'
    assert_includes body, "/teams/#{@team.id}/monitor/install"
  end

  it 'shows remove button for each repo' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="remove-repo"'
    assert_includes body, "/teams/#{@team.id}/monitor/repos/#{@repo.id}/remove"
  end

  it 'shows disconnect button' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="disconnect-monitor"'
    assert_includes body, "/teams/#{@team.id}/monitor/disconnect"
  end

  it 'shows summary when no push to trunk' do
    @repo.update(last_push_at: nil)

    visit_monitor(@team)

    body = page_body

    assert_open_branches(body, 0)
    assert_includes body, 'data-test-id="monitor-summary"'
  end

  it 'shows over-threshold count when branch exceeds threshold' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/stale',
      status:            'open',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    assert_open_branches(body, 1)
    assert_includes body, 'data-test-id="monitor-over-threshold" data-count="1"'
    assert_includes body, 'data-test-id="monitor-summary"'
  end

  it 'verdict says not doing CI when any branch exceeds threshold' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/stale',
      status:            'open',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="monitor-verdict" data-doing-ci="false"'
  end

  it 'verdict says doing CI when no branches exceed threshold' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="monitor-verdict" data-doing-ci="true"'
  end

  it 'shows repo row with status' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'acme/webapp'
    assert_includes body, 'data-test-id="repo-row"'
  end

  it 'shows gaming section on dashboard' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="gaming-section"'
  end

  it 'shows footer copy on dashboard' do
    visit_monitor(@team)

    body = page_body

    assert_shown('monitor-footer', body)
  end

  it 'shows offending branches for red repo' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/old',
      status:            'open',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    assert_includes body, 'feature/old'
  end

  it 'shows recently abandoned branch on dashboard' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/gaming',
      status:            'abandoned',
      abandoned_at:      Time.now - (12 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    assert_includes body, 'feature/gaming'
    assert_includes body, 'data-test-id="abandoned-row"'
  end

  it 'hides abandoned branch outside goal window' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/old',
      status:            'abandoned',
      abandoned_at:      Time.now - (73 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    refute_includes body, 'feature/old'
  end

  it 'shows branch age for open branches' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/aging',
      status:            'open',
      created_at:        Time.now - (10 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    assert_includes body, 'feature/aging'
    assert_includes body, 'data-test-id="branch-age"'
  end

  it 'shows recently merged branch on dashboard' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/done',
      status:            'merged',
      merged_at:         Time.now - (6 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    assert_includes body, 'feature/done'
    assert_includes body, 'data-test-id="merged-row"'
  end

  it 'shows warning when merged branch was previously spiked' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/sneaky',
      status:            'merged',
      merged_at:         Time.now - (6 * 3600),
      merged_from_spike: true
    )

    visit_monitor(@team)

    body = page_body

    assert_includes body, 'spike/sneaky'
    assert_includes body, 'data-test-id="merged-from-spike"'
  end

  it 'hides merged branch outside goal window' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/ancient',
      status:            'merged',
      merged_at:         Time.now - (73 * 3600)
    )

    visit_monitor(@team)

    body = page_body

    refute_includes body, 'feature/ancient'
  end
end

describe 'CI Monitor - zero repos' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
  end

  it 'Dashboard.load returns none status with zero repos' do
    data = CIMonitor::Dashboard.load(@team.id, 24, @team.timezone)

    assert_equal :none, data[:overall_status]
    assert_equal 0, data[:total_open]
    assert_equal 0, data[:total_over]
    assert_empty data[:repo_data]
  end
end

describe 'CI Monitor - heatmap mode toggle' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
    @repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      last_push_at:             Time.now,
      threshold_hours:          24
    )
  end

  it 'defaults to average heatmap mode' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="heatmap-mode"'
  end

  it 'toggles heatmap mode from max to average' do
    driver.post "/teams/#{@team.id}/monitor/heatmap-mode", 'mode' => 'average'

    @team.refresh

    assert_equal 'average', @team.heatmap_mode
  end

  it 'toggles heatmap mode from average to max' do
    @team.update(heatmap_mode: 'average')
    driver.post "/teams/#{@team.id}/monitor/heatmap-mode", 'mode' => 'max'

    @team.refresh

    assert_equal 'max', @team.heatmap_mode
  end

  it 'rejects invalid heatmap mode' do
    driver.post "/teams/#{@team.id}/monitor/heatmap-mode", 'mode' => 'garbage'

    @team.refresh

    assert_equal 'average', @team.heatmap_mode
  end
end

describe 'CI Monitor - spike marking' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
    @repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      last_push_at:             Time.now,
      threshold_hours:          24
    )
  end

  it 'marks branch as spike' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/experiment',
      status:            'open',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    mark_spike(branch)

    branch.refresh

    assert_equal 'spike', branch.status
  end

  it 'spike branch excluded from red calculation' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/experiment',
      status:            'open',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    # Before marking spike - should show over threshold
    visit_monitor(@team)

    assert_includes page_body, 'data-test-id="monitor-over-threshold" data-count="1"'

    branch = TrackedBranch.where(monitored_repo_id: @repo.id).first
    mark_spike(branch)

    # After marking spike - should show 0 open
    visit_monitor(@team)

    assert_open_branches(page_body, 0)
    refute_shown('monitor-over-threshold', page_body)
  end

  it 'spike branch still visible with label' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/experiment',
      status:            'open',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    mark_spike(branch)

    visit_monitor(@team)

    body = page_body

    assert_includes body, 'spike/experiment'
    assert_includes body, 'spike'
  end

  it 'unmarks spike back to open' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/experiment',
      status:            'spike',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    unmark_spike(branch)

    branch.refresh

    assert_equal 'open', branch.status
  end

  it 'unmarked spike counts toward red again' do
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'spike/experiment',
      status:            'spike',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    visit_monitor(@team)

    assert_open_branches(page_body, 0)

    unmark_spike(branch)

    visit_monitor(@team)

    assert_includes page_body, 'data-test-id="monitor-over-threshold" data-count="1"'
  end
end

describe 'CI Monitor - repo picker' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
    @fake_repos = [
      { id: 200, full_name: 'acme/api', default_branch: 'main' },
      { id: 300, full_name: 'acme/docs', default_branch: 'master' }
    ]
  end

  it 'shows available repos from GitHub grouped by org' do
    body = visit_repo_picker(@team, stub_repos: @fake_repos)

    assert_includes body, 'data-test-id="repo-picker"'
    assert_includes body, 'data-test-id="org-group-acme"'
    assert_includes body, '>api</span>'
    assert_includes body, '>docs</span>'
  end

  it 'groups repos by org with per-org toggle' do
    multi_org_repos = [
      { id: 200, full_name: 'acme/api', default_branch: 'main' },
      { id: 300, full_name: 'acme/docs', default_branch: 'main' },
      { id: 400, full_name: 'widgets-inc/frontend', default_branch: 'main' }
    ]
    body = visit_repo_picker(@team, stub_repos: multi_org_repos)

    assert_includes body, 'data-test-id="org-group-acme"'
    assert_includes body, 'data-test-id="org-group-widgets-inc"'
    assert_includes body, 'data-test-id="org-toggle"'
  end

  it 'imports selected repos' do
    import_repos(@team, repos: @fake_repos, selected: [200], stub_repos: @fake_repos)

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first

    refute_nil repo
    assert_equal 'acme/api', repo.repo_name
    assert_equal 'main', repo.default_branch
    assert_equal 24, repo.threshold_hours
  end

  it 'imported repo without commit history starts amber not green' do
    import_repos(@team, repos: @fake_repos, selected: [200], stub_repos: @fake_repos)

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first

    assert_nil repo.last_push_at

    status = CIMonitor::Status.for_repo(repo, [], @team.timezone)

    assert_equal :amber, status
  end

  it 'imports multiple selected repos' do
    import_repos(@team, repos: @fake_repos, selected: [200, 300], stub_repos: @fake_repos)

    repos = MonitoredRepo.where(team_id: @team.id).all

    assert_equal 2, repos.size
  end

  it 'backfills existing branches on import' do
    stub_branches = {
      'acme/api' => [
        { name: 'main', commit: { sha: 'abc123' } },
        { name: 'feature/auth', commit: { sha: 'def456' } },
        { name: 'fix/typo', commit: { sha: 'ghi789' } }
      ]
    }

    import_repos(
      @team, repos: @fake_repos, selected: [200],
      stub_repos: @fake_repos, stub_branches: stub_branches
    )

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first
    branches = BypassRLS.call { TrackedBranch.where(monitored_repo_id: repo.id).all }

    assert_equal 2, branches.size
    names = branches.map(&:branch_name).sort

    assert_equal %w[feature/auth fix/typo], names
  end

  it 'does not backfill a repo belonging to another team' do
    import_repos(@team, repos: @fake_repos, selected: [200], stub_repos: @fake_repos)
    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first
    BypassRLS.call { MonitoredRepo.where(id: repo.id).update(backfill_status: 'pending') }
    other_team = Team.create(name: 'Other')

    branches = [
      { name: 'main', commit: { sha: 'abc123' } },
      { name: 'feature/auth', commit: { sha: 'def456' } }
    ]
    CIMonitor::GithubAPI.stub(:repo_branches, ->(*) { branches }) do
      CIMonitor::GithubAPI.stub(:commit_date, Time.now) do
        CIMonitor::GithubAPI.stub(:default_branch_commits, ->(*_, **) { [] }) do
          CIMonitor::GithubAPI.stub(:merged_pulls, ->(*_, **) { [] }) do
            CIMonitor::RepoBackfill.call(
              repo_id: repo.id, team_id: other_team.id,
              installation_id: repo.provider_installation_id, default_branch: 'main'
            )
          end
        end
      end
    end

    count = BypassRLS.call { TrackedBranch.where(monitored_repo_id: repo.id).count }

    assert_equal 0, count
    assert_equal 'pending', BypassRLS.call { MonitoredRepo[repo.id] }.backfill_status
  end

  it 'does not create duplicate branches when branch already tracked' do
    branch_lookup = lambda { |_inst_id, full_name|
      next [] unless full_name == 'acme/api'

      repo = BypassRLS.call { MonitoredRepo.where(provider_repo_id: 200).first }
      BypassRLS.call do
        TrackedBranch.create(
          monitored_repo_id: repo.id, branch_name: 'feature/auth',
          head_sha: 'def456', status: 'open'
        )
      end
      [
        { name: 'main', commit: { sha: 'abc123' } },
        { name: 'feature/auth', commit: { sha: 'def456' } }
      ]
    }

    params = { 'repo_ids' => ['200'] }
    CIMonitor::GithubAPI.stub(:installation_repos, @fake_repos) do
      CIMonitor::GithubAPI.stub(:repo_branches, branch_lookup) do
        CIMonitor::GithubAPI.stub(:commit_date, Time.now) do
          CIMonitor::GithubAPI.stub(:default_branch_commits, ->(*_, **) { [] }) do
            CIMonitor::GithubAPI.stub(:merged_pulls, ->(*_, **) { [] }) do
              driver.post "/teams/#{@team.id}/monitor/repos/import", params
            end
          end
        end
      end
    end

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first
    count = BypassRLS.call { TrackedBranch.where(monitored_repo_id: repo.id).count }

    assert_equal 1, count
  end

  it 'backfills branches with commit date as created_at' do
    commit_date = Time.utc(2026, 4, 1, 12, 0, 0)
    stub_branches = {
      'acme/api' => [
        { name: 'main', commit: { sha: 'abc123' } },
        { name: 'feature/old', commit: { sha: 'def456' } }
      ]
    }
    stub_commit_dates = { 'def456' => commit_date }

    import_repos(
      @team, repos: @fake_repos, selected: [200],
      stub_repos: @fake_repos, stub_branches: stub_branches,
      stub_commit_dates: stub_commit_dates
    )

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first
    branch = BypassRLS.call { TrackedBranch.where(monitored_repo_id: repo.id).first }

    assert_equal commit_date.to_i, branch.created_at.to_i
  end

  it 'skips default branch during backfill' do
    stub_branches = {
      'acme/docs' => [
        { name: 'master', commit: { sha: 'abc123' } },
        { name: 'update-readme', commit: { sha: 'def456' } }
      ]
    }

    import_repos(
      @team, repos: @fake_repos, selected: [300],
      stub_repos: @fake_repos, stub_branches: stub_branches
    )

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 300).first
    branches = BypassRLS.call { TrackedBranch.where(monitored_repo_id: repo.id).all }

    assert_equal 1, branches.size
    assert_equal 'update-readme', branches.first.branch_name
  end

  it 'backfills integration events from commit history on import' do
    stub_commits = [
      { sha: 'aaa', date: Time.utc(2026, 4, 10, 12, 0, 0) },
      { sha: 'bbb', date: Time.utc(2026, 4, 11, 14, 0, 0) }
    ]
    stub_pulls = [
      { branch: 'feature/x', merged_at: Time.utc(2026, 4, 12, 10, 0, 0) }
    ]

    import_repos(
      @team, repos: @fake_repos, selected: [200],
      stub_repos: @fake_repos, stub_commits: stub_commits, stub_pulls: stub_pulls
    )

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first
    events = BypassRLS.call { IntegrationEvent.where(monitored_repo_id: repo.id).all }
    pushes = events.select { |e| e.event_type == 'push' }
    merges = events.select { |e| e.event_type == 'merge' }

    assert_equal 2, pushes.size
    assert_equal 1, merges.size
  end

  it 'links backfilled merge events to matching tracked branches' do
    stub_branches = {
      'acme/api' => [{ name: 'feature/x', commit: { sha: 'fff' } }]
    }
    stub_commit_dates = { 'fff' => Time.utc(2026, 4, 9, 10, 0, 0) }
    stub_pulls = [
      { branch: 'feature/x', merged_at: Time.utc(2026, 4, 12, 10, 0, 0) }
    ]

    import_repos(
      @team, repos: @fake_repos, selected: [200],
      stub_repos: @fake_repos, stub_branches: stub_branches,
      stub_commit_dates: stub_commit_dates, stub_pulls: stub_pulls
    )

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first
    branch = BypassRLS.call {
      TrackedBranch.where(monitored_repo_id: repo.id).first
    }
    merge_event = BypassRLS.call {
      IntegrationEvent.where(monitored_repo_id: repo.id, event_type: 'merge').first
    }

    assert_equal 'merged', branch.status
    refute_nil branch.merged_at
    assert_equal branch.id, merge_event.tracked_branch_id
  end

  it 'sets merged_from_spike when backfilled branch was spiked' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         200,
      repo_name:                'acme/api',
      default_branch:           'main',
      last_push_at:             Time.now
    )
    branch = TrackedBranch.create(
      monitored_repo_id: repo.id,
      branch_name:       'feature/experiment',
      head_sha:          'ggg',
      status:            'spike',
      created_at:        Time.utc(2026, 4, 1, 10, 0, 0)
    )

    stub_pulls = [
      { branch: 'feature/experiment', merged_at: Time.utc(2026, 4, 12, 10, 0, 0) }
    ]
    CIMonitor::GithubAPI.stub(:default_branch_commits, ->(*_a, **) { [] }) do
      CIMonitor::GithubAPI.stub(:merged_pulls, ->(*_a, **) { stub_pulls }) do
        CIMonitor::RepoBackfill.send(:backfill_events, repo, 12345, 'main')
      end
    end

    branch.refresh

    assert branch.merged_from_spike, 'branch should be flagged as merged from spike'
  end

  it 'shows warning when GitHub API fails on repo picker' do
    error = CIMonitor::GithubAPI::Error.new('GitHub API error (401)')
    visit_repo_picker(@team, stub_repos: error)
    visit_monitor(@team)

    body = page_body

    assert_shown('flash-warning', body)
  end

  it 'skips already-monitored repos in picker' do
    MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         200,
      repo_name:                'acme/api',
      default_branch:           'main'
    )

    body = visit_repo_picker(@team, stub_repos: @fake_repos)

    assert_includes body, '>docs</span>'
    refute_includes body, 'value="200"'
  end

  it 'skips duplicate on import' do
    MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         200,
      repo_name:                'acme/api',
      default_branch:           'main'
    )

    import_repos(@team, repos: @fake_repos, selected: [200, 300], stub_repos: @fake_repos)

    assert_equal 1, MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).count
    refute_nil MonitoredRepo.where(team_id: @team.id, provider_repo_id: 300).first
  end

  it 'imports from surviving installation when another installation API call fails' do
    connect_github_installation(67890)
    failing_repos = lambda { |inst_id|
      raise CIMonitor::GithubAPI::Error, 'revoked' if inst_id == 12345

      [{ id: 400, full_name: 'other-org/app', default_branch: 'main' }]
    }

    import_repos(@team, selected: [400], stub_repos: failing_repos)

    refute_nil MonitoredRepo.where(team_id: @team.id, provider_repo_id: 400).first
  end

  it 'handles import with no repos selected' do
    CIMonitor::GithubAPI.stub(:installation_repos, @fake_repos) do
      driver.post "/teams/#{@team.id}/monitor/repos/import", {}
    end

    assert_equal 0, MonitoredRepo.where(team_id: @team.id).count
  end

  it 'continues backfilling other repos when one fails' do
    call_count = 0
    failing_branches = lambda { |_inst_id, full_name|
      call_count += 1
      raise CIMonitor::GithubAPI::Error, 'timeout' if full_name == 'acme/api'

      [{ name: 'master', commit: { sha: 'a1' } }, { name: 'hotfix', commit: { sha: 'b2' } }]
    }

    params = { 'repo_ids' => %w[200 300] }
    CIMonitor::GithubAPI.stub(:installation_repos, @fake_repos) do
      CIMonitor::GithubAPI.stub(:repo_branches, failing_branches) do
        CIMonitor::GithubAPI.stub(:commit_date, Time.now) do
          CIMonitor::GithubAPI.stub(:default_branch_commits, ->(*_, **) { [] }) do
            CIMonitor::GithubAPI.stub(:merged_pulls, ->(*_, **) { [] }) do
              driver.post "/teams/#{@team.id}/monitor/repos/import", params
            end
          end
        end
      end
    end

    assert_equal 302, driver.last_response.status
    assert_equal 2, call_count
    docs_repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 300).first
    branches = BypassRLS.call { TrackedBranch.where(monitored_repo_id: docs_repo.id).all }

    assert_equal 1, branches.size
    assert_equal 'hotfix', branches.first.branch_name
  end

  it 'enqueues pending repos on dashboard load' do
    import_repos(@team, repos: @fake_repos, selected: [200], stub_repos: @fake_repos)
    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 200).first
    BypassRLS.call { MonitoredRepo.where(id: repo.id).update(backfill_status: 'pending') }

    CIMonitor::GithubAPI.stub(:repo_branches, ->(*_) { [] }) do
      CIMonitor::GithubAPI.stub(:default_branch_commits, ->(*_, **) { [] }) do
        CIMonitor::GithubAPI.stub(:merged_pulls, ->(*_, **) { [] }) do
          visit_monitor(@team)
        end
      end
    end

    repo.refresh

    assert_equal 'complete', repo.backfill_status
  end
end

describe 'CI Monitor - repo management' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
  end

  it 'removes a watched repo with branches' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         888,
      repo_name:                'acme/api',
      default_branch:           'main'
    )
    TrackedBranch.create(
      monitored_repo_id: repo.id,
      branch_name:       'feature/old',
      status:            'open'
    )

    remove_monitored_repo(repo)

    assert_nil MonitoredRepo[repo.id]
  end

  it 'removes a repo that has integration events' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         889,
      repo_name:                'acme/evented',
      default_branch:           'main'
    )
    branch = TrackedBranch.create(
      monitored_repo_id: repo.id,
      branch_name:       'feature/x',
      status:            'merged',
      merged_at:         Time.now
    )
    IntegrationEvent.create(
      monitored_repo_id: repo.id,
      event_type:        'merge',
      occurred_at:       Time.now,
      tracked_branch_id: branch.id
    )
    IntegrationEvent.create(
      monitored_repo_id: repo.id,
      event_type:        'push',
      occurred_at:       Time.now
    )

    remove_monitored_repo(repo)

    assert_nil MonitoredRepo[repo.id]
    assert_equal 0, IntegrationEvent.where(monitored_repo_id: repo.id).count
  end

  it 'disconnect removes repos with integration events' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         890,
      repo_name:                'acme/full',
      default_branch:           'main'
    )
    IntegrationEvent.create(
      monitored_repo_id: repo.id,
      event_type:        'push',
      occurred_at:       Time.now
    )

    disconnect_monitor(@team)

    assert_equal 0, MonitoredRepo.where(team_id: @team.id).count
    assert_equal 0, IntegrationEvent.where(monitored_repo_id: repo.id).count
  end

  it 'updates summary after removing a repo' do
    repo_a = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 12345,
      provider_repo_id: 801, repo_name: 'acme/api', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
    repo_b = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 12345,
      provider_repo_id: 802, repo_name: 'acme/web', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
    TrackedBranch.create(
      monitored_repo_id: repo_a.id, branch_name: 'feat/a', status: 'open'
    )
    TrackedBranch.create(
      monitored_repo_id: repo_b.id, branch_name: 'feat/b', status: 'open'
    )

    visit_monitor(@team)

    assert_open_branches(page_body, 2)

    remove_monitored_repo(repo_a)
    visit_monitor(@team)

    assert_open_branches(page_body, 1)
  end

  it 'updates threshold for a repo' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         777,
      repo_name:                'acme/webapp',
      default_branch:           'main'
    )

    update_repo_threshold(repo, threshold_hours: 8)

    repo.refresh

    assert_equal 8, repo.threshold_hours
  end

  it 'rejects invalid threshold' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         777,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      threshold_hours:          24
    )

    update_repo_threshold(repo, threshold_hours: 99)

    repo.refresh

    assert_equal 24, repo.threshold_hours
  end

  it 'threshold select auto-submits on change' do
    MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         777,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      threshold_hours:          24,
      last_push_at:             Time.now
    )

    visit_monitor(@team)
    body = page_body

    assert_includes body, 'onchange', 'threshold select should auto-submit on change'
  end

  it 'rejects duplicate repo' do
    MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         777,
      repo_name:                'acme/webapp',
      default_branch:           'main'
    )

    add_monitored_repo(
      @team,
      provider_repo_id: 777,
      repo_name:        'acme/webapp',
      default_branch:   'main'
    )

    assert_equal 1, MonitoredRepo.where(team_id: @team.id, provider_repo_id: 777).count
  end

  it 'disconnect removes all repos and clears installation' do
    repo = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 12345,
      provider_repo_id: 900, repo_name: 'acme/app', default_branch: 'main'
    )
    TrackedBranch.create(
      monitored_repo_id: repo.id, branch_name: 'feat/x', status: 'open'
    )

    disconnect_monitor(@team)

    assert_equal 0, TeamInstallation.where(team_id: @team.id).count
    assert_equal 0, MonitoredRepo.where(team_id: @team.id).count
    assert_equal 0, TrackedBranch.where(monitored_repo_id: repo.id).count
  end

  it 'disconnect returns to connect screen' do
    MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 12345,
      provider_repo_id: 901, repo_name: 'acme/web', default_branch: 'main'
    )

    disconnect_monitor(@team)
    visit_monitor(@team)

    assert_shown('monitor-connect', page_body)
  end
end

describe 'CI Monitor - thresholds' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
  end

  it 'repo threshold capped at 24h' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      threshold_hours:          24
    )

    update_repo_threshold(repo, threshold_hours: 72)

    repo.refresh

    assert_equal 24, repo.threshold_hours
  end

  it 'new repo defaults to 24h threshold' do
    add_monitored_repo(
      @team,
      provider_repo_id: 777,
      repo_name:        'acme/webapp',
      default_branch:   'main'
    )

    repo = MonitoredRepo.where(team_id: @team.id, provider_repo_id: 777).first

    assert_equal 24, repo.threshold_hours
  end

  it 'allows tightening threshold below 24h' do
    repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      threshold_hours:          24
    )

    update_repo_threshold(repo, threshold_hours: 8)

    repo.refresh

    assert_equal 8, repo.threshold_hours
  end

  it 'summary shows open branch count' do
    MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      last_push_at:             Time.now,
      threshold_hours:          24
    )

    visit_monitor(@team)

    assert_open_branches(page_body, 0)
  end
end

describe 'CI Monitor - cross-team isolation' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
    @repo = MonitoredRepo.create(
      team_id:                  @team.id,
      provider_installation_id: 12345,
      provider_repo_id:         100,
      repo_name:                'acme/webapp',
      default_branch:           'main',
      last_push_at:             Time.now,
      threshold_hours:          24
    )
    @branch = TrackedBranch.create(
      monitored_repo_id: @repo.id,
      branch_name:       'feature/secret',
      status:            'open',
      created_at:        Time.now - (5 * 24 * 3600)
    )

    @other_team = Team.create(name: 'Other Team')
    @eve = Person.create(name: 'Eve', email: 'eve@evil.co')
    TeamMembership.create(team_id: @other_team.id, person_id: @eve.id)
    login_as(@eve)
  end

  it 'cannot view another teams monitor' do
    resp = driver.get "/teams/#{@team.id}/monitor"

    assert_equal 403, resp.status
  end

  it 'cannot mark spike on another teams branch' do
    resp = driver.post "/teams/#{@team.id}/monitor/branches/#{@branch.id}/spike"

    assert_equal 403, resp.status
    SetTeamContext.call(@team.id)
    @branch.refresh

    assert_equal 'open', @branch.status
  end

  it 'cannot remove another teams repo' do
    resp = driver.post "/teams/#{@team.id}/monitor/repos/#{@repo.id}/remove"

    assert_equal 403, resp.status
    SetTeamContext.call(@team.id)

    refute_nil MonitoredRepo[@repo.id]
  end

  it 'cannot disconnect another teams monitor' do
    resp = driver.post "/teams/#{@team.id}/monitor/disconnect"

    assert_equal 403, resp.status
    SetTeamContext.call(@team.id)

    assert_equal 1, TeamInstallation.where(team_id: @team.id).count
  end
end

describe 'CI Monitor - single-repo POST installation ownership' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
  end

  it 'rejects repo creation with installation_id not belonging to team' do
    before_count = MonitoredRepo.where(team_id: @team.id).count

    add_monitored_repo(
      @team,
      provider_repo_id: 999,
      repo_name:        'evil/repo',
      default_branch:   'main',
      installation_id:  99999
    )

    assert_equal before_count, MonitoredRepo.where(team_id: @team.id).count
  end

  it 'accepts repo creation with installation_id belonging to team' do
    add_monitored_repo(
      @team,
      provider_repo_id: 999,
      repo_name:        'acme/legit',
      default_branch:   'main',
      installation_id:  12345
    )

    refute_nil MonitoredRepo.where(team_id: @team.id, provider_repo_id: 999).first
  end
end

describe 'CI Monitor - installation verification' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    ENV['CI_MONITOR_GITHUB_APP_SLUG'] = 'mainline-ci-monitor'
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_ID'] = 'test-client-id'
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_SECRET'] = 'test-client-secret'
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'rejects installation_id not owned by user' do
    app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID').to_i
    user_installations = [{ app_id: app_id, id: 11111, account_login: 'legit-org' }]

    driver.post '/_test_login', {
      'person_id'        => @alice.id,
      'ci_monitor_token' => 'valid-token'
    }

    CIMonitor::GithubAPI.stub(:user_installations, ->(_token) { user_installations }) do
      driver.post "/teams/#{@team.id}/monitor/install", {
        'installation_id' => '99999',
        'account_login'   => 'evil-corp'
      }
    end

    assert_nil TeamInstallation.where(team_id: @team.id, installation_id: 99999).first
  end
end

describe 'CI Monitor - org-grouped dashboard' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
    @repo_acme = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 12345,
      provider_repo_id: 100, repo_name: 'acme/api',
      default_branch: 'main', threshold_hours: 24, last_push_at: Time.now
    )
    @repo_widgets = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 12345,
      provider_repo_id: 200, repo_name: 'widgets/frontend',
      default_branch: 'main', threshold_hours: 24, last_push_at: Time.now
    )
  end

  it 'groups repos under org headings' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="org-group-acme"'
    assert_includes body, 'data-test-id="org-group-widgets"'
  end

  it 'shows org-level heatmap for each org' do
    visit_monitor(@team)

    body = page_body

    assert_includes body, 'data-test-id="org-streak-acme"'
    assert_includes body, 'data-test-id="org-streak-widgets"'
  end

  it 'shows repos inside their org group' do
    visit_monitor(@team)

    body = page_body

    acme_section = body[%r{data-test-id="org-group-acme".*?(?=data-test-id="org-group-|</div>\s*<div class="monitor-actions")}m]
    widgets_section = body[%r{data-test-id="org-group-widgets".*?(?=data-test-id="org-group-|</div>\s*<div class="monitor-actions")}m]

    assert_includes acme_section, 'acme/api'
    assert_includes widgets_section, 'widgets/frontend'
    refute_includes acme_section, 'widgets/frontend'
    refute_includes widgets_section, 'acme/api'
  end
end
