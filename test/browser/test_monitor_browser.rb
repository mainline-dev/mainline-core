# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/ci_monitor_dsl'

describe 'CI Monitor (browser)' do
  include MainlineDSL
  include CIMonitorDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    connect_github_installation(12345)
    BypassRLS.call do
      @repo = MonitoredRepo.create(
        team_id: @team.id, provider_installation_id: 12345,
        provider_repo_id: 1001, repo_name: 'acme/web',
        default_branch: 'main', threshold_hours: 24, last_push_at: Time.now
      )
    end
  end

  it 'auto-submits threshold select via HTMX' do
    use_browser!
    visit "/teams/#{@team.id}/monitor"

    assert_selector '[data-test-id="repo-row"]'
    find('[data-test-id="repo-toggle"]').click

    within '[data-test-id="repo-row"]' do
      select '16h', from: 'threshold_hours'
    end

    assert_selector '[data-test-id="repo-row"]', wait: 5
    @repo.refresh

    assert_equal 16, @repo.threshold_hours
  end

  it 'delete-confirm pattern works for remove repo' do
    use_browser!
    visit "/teams/#{@team.id}/monitor"

    find('[data-test-id="repo-toggle"]').click
    btn = find('[data-test-id="remove-repo"]')

    assert_equal 'REMOVE', btn.text

    btn.click

    assert_equal 'CONFIRM?', btn.text

    btn.click

    assert_no_selector '[data-test-id="repo-row"]'
  end

  it 'spike button updates dashboard in-page via JS' do
    BypassRLS.call do
      TrackedBranch.create(
        monitored_repo_id: @repo.id, branch_name: 'feature/old',
        status: 'open', created_at: Time.now - (5 * 24 * 3600)
      )
    end
    use_browser!
    visit "/teams/#{@team.id}/monitor"

    assert_selector '[data-test-id="branch-row"]'
    assert_selector '.monitor-spike-btn'

    find('.monitor-spike-btn').click

    find('[data-test-id="repo-toggle"]').click

    assert_selector '.monitor-branch--spike'
    assert_selector '.monitor-unspike-btn'
    assert_no_selector '.monitor-spike-btn'
  end

  it 'disconnect via HTMX redirects to connect page' do
    use_browser!
    visit "/teams/#{@team.id}/monitor"

    btn = find('[data-test-id="disconnect-monitor"]')

    assert_equal 'Disconnect', btn.text

    btn.click

    assert_equal 'confirm?', btn.text

    btn.click

    assert_selector '[data-test-id="monitor-connect"]'
  end

  it 'unspike button restores branch to open via JS' do
    BypassRLS.call do
      TrackedBranch.create(
        monitored_repo_id: @repo.id, branch_name: 'spike/experiment',
        status: 'spike', created_at: Time.now - (5 * 24 * 3600)
      )
    end
    use_browser!
    visit "/teams/#{@team.id}/monitor"

    find('[data-test-id="repo-toggle"]').click

    assert_selector '.monitor-unspike-btn'

    find('.monitor-unspike-btn').click

    assert_selector '.monitor-spike-btn'
    assert_no_selector '.monitor-unspike-btn'
  end

  it 'renders repos grouped by org with org heatmaps' do
    BypassRLS.call do
      MonitoredRepo.create(
        team_id: @team.id, provider_installation_id: 12345,
        provider_repo_id: 2002, repo_name: 'widgets/frontend',
        default_branch: 'main', threshold_hours: 24, last_push_at: Time.now
      )
    end
    use_browser!
    visit "/teams/#{@team.id}/monitor"

    assert_selector '[data-test-id="org-group-acme"]'
    assert_selector '[data-test-id="org-group-widgets"]'
    assert_selector '[data-test-id="org-streak-acme"]'
    assert_selector '[data-test-id="org-streak-widgets"]'

    within '[data-test-id="org-group-acme"]' do
      assert_text 'acme/web'
    end
    within '[data-test-id="org-group-widgets"]' do
      assert_text 'widgets/frontend'
    end
  end
end
