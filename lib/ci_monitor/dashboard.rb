# frozen_string_literal: true

module CIMonitor
  module Dashboard
    DEFAULT_THRESHOLD_HOURS = 24
    RECENT_WINDOW_HOURS = 24
    VALID_THRESHOLDS = [8, 16, 24].freeze

    def self.load(team_id, goal, timezone, holiday_region: nil)
      now = Time.now
      repos = MonitoredRepo.where(team_id: team_id).order(:created_at).all
      repo_data = repos.map { |repo| build_repo_data(repo, goal, timezone, now, holiday_region) }
      overall_status = Status.overall(repo_data.map { |d| d[:status] })
      total_open = repo_data.sum { |d| d[:branches].size }
      total_over = repo_data.sum { |d|
        d[:branches].count { |b| d[:ages][b.id] > d[:repo].threshold_hours }
      }
      { repo_data: repo_data, overall_status: overall_status,
        total_open: total_open, total_over: total_over }
    end

    def self.build_repo_data(repo, goal, timezone, now, holiday_region)
      open_branches = TrackedBranch.where(monitored_repo_id: repo.id, status: 'open').all
      spike_branches = TrackedBranch.where(monitored_repo_id: repo.id, status: 'spike').all
      abandoned_branches = TrackedBranch.where(monitored_repo_id: repo.id, status: 'abandoned')
        .where { abandoned_at > now - (goal * 3600) }.all
      merged_branches = TrackedBranch.where(monitored_repo_id: repo.id, status: 'merged')
        .where { merged_at > now - (goal * 3600) }.all
      status = Status.for_repo(repo, open_branches, timezone, now: now, holiday_region: holiday_region)
      branch_ages = (open_branches + spike_branches).to_h { |b|
        [b.id, BranchAge.hours(b.created_at, now, timezone, holiday_region: holiday_region)]
      }
      { repo: repo, status: status, branches: open_branches, spikes: spike_branches,
        abandoned: abandoned_branches, merged: merged_branches, ages: branch_ages }
    end

    private_class_method :build_repo_data
  end
end
