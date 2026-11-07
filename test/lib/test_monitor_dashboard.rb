# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/ci_monitor/branch_age'
require_relative '../../lib/ci_monitor/status'
require_relative '../../lib/ci_monitor/dashboard'

describe 'CIMonitor::Dashboard.load' do
  before do
    @team = Team.create(name: 'DashTest')
    SetTeamContext.call(@team.id)
    TeamInstallation.create(
      team_id: @team.id, provider: 'github', installation_id: 1, org_name: 'acme'
    )
  end

  it 'uses a consistent timestamp across all repos' do
    repo_a = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 100,
      repo_name: 'acme/alpha', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
    repo_b = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 200,
      repo_name: 'acme/beta', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
    TrackedBranch.create(
      monitored_repo_id: repo_a.id, branch_name: 'feat-a',
      head_sha: 'aaa', status: 'open', created_at: Time.now - (12 * 3600)
    )
    TrackedBranch.create(
      monitored_repo_id: repo_b.id, branch_name: 'feat-b',
      head_sha: 'bbb', status: 'open', created_at: Time.now - (12 * 3600)
    )

    result = CIMonitor::Dashboard.load(@team.id, 24, 'UTC')

    assert_equal 2, result[:total_open]
    assert_equal 0, result[:total_over]
  end

  it 'uses recent_window_hours independently of repo threshold' do
    repo = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 300,
      repo_name: 'acme/gamma', default_branch: 'main',
      threshold_hours: 8, last_push_at: Time.now
    )
    TrackedBranch.create(
      monitored_repo_id: repo.id, branch_name: 'old-merge',
      head_sha: 'ccc', status: 'merged', created_at: Time.now - (20 * 3600),
      merged_at: Time.now - (20 * 3600)
    )

    result_wide = CIMonitor::Dashboard.load(@team.id, 24, 'UTC')

    assert_equal 1, result_wide[:repo_data].first[:merged].size

    result_narrow = CIMonitor::Dashboard.load(@team.id, 12, 'UTC')

    assert_equal 0, result_narrow[:repo_data].first[:merged].size
  end

  it 'ages map contains hours for open and spike branches' do
    # Use a known Wednesday so business hours are always counted
    wednesday_noon = Time.utc(2026, 5, 13, 12, 0, 0)
    repo = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 400,
      repo_name: 'acme/delta', default_branch: 'main',
      threshold_hours: 24, last_push_at: wednesday_noon
    )
    open_branch = TrackedBranch.create(
      monitored_repo_id: repo.id, branch_name: 'feat-open',
      head_sha: 'ddd', status: 'open', created_at: wednesday_noon - (4 * 3600)
    )
    spike_branch = TrackedBranch.create(
      monitored_repo_id: repo.id, branch_name: 'feat-spike',
      head_sha: 'eee', status: 'spike', created_at: wednesday_noon - (2 * 3600)
    )
    abandoned_branch = TrackedBranch.create(
      monitored_repo_id: repo.id, branch_name: 'feat-abandoned',
      head_sha: 'fff', status: 'abandoned', created_at: wednesday_noon - (3 * 3600),
      abandoned_at: wednesday_noon - (1 * 3600)
    )

    Time.stub(:now, wednesday_noon) do
      result = CIMonitor::Dashboard.load(@team.id, 24, 'UTC')
      ages = result[:repo_data].first[:ages]

      assert_includes ages.keys, open_branch.id
      assert_includes ages.keys, spike_branch.id
      refute_includes ages.keys, abandoned_branch.id
      assert_equal 4, ages[open_branch.id]
      assert_equal 2, ages[spike_branch.id]
    end
  end

  it 'holiday_region reduces branch age by excluding holidays' do
    # Australia Day 2026: Mon Jan 26
    # Branch created Fri Jan 23 at noon, check on Tue Jan 27 at noon
    repo = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 500,
      repo_name: 'acme/holiday', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.utc(2026, 1, 26, 12, 0, 0)
    )
    TrackedBranch.create(
      monitored_repo_id: repo.id, branch_name: 'feat/holiday',
      status: 'open', created_at: Time.utc(2026, 1, 23, 0, 0, 0)
    )

    tue_noon = Time.utc(2026, 1, 27, 0, 0, 0)

    Time.stub(:now, tue_noon) do
      without = CIMonitor::Dashboard.load(@team.id, 24, 'UTC')
      with_ph = CIMonitor::Dashboard.load(@team.id, 24, 'UTC', holiday_region: 'au')

      age_without = without[:repo_data].find { |d| d[:repo].id == repo.id }[:ages].values.first
      age_with = with_ph[:repo_data].find { |d| d[:repo].id == repo.id }[:ages].values.first

      assert_equal 48, age_without  # Fri + Mon = 48h
      assert_equal 24, age_with     # Fri only, Mon is holiday = 24h
    end
  end
end
