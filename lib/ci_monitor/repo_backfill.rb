# frozen_string_literal: true

module CIMonitor
  module RepoBackfill
    def self.call(repo_id:, installation_id:, default_branch:, team_id:)
      DB.transaction do
        SetTeamContext.call(team_id)
        repo = MonitoredRepo[repo_id]
        unless repo
          warn "RepoBackfill: repo #{repo_id} not found"
          next
        end

        backfill_branches(repo, installation_id, default_branch)
        MonitoredRepo.where(id: repo_id).update(backfill_status: 'complete')
      end
    rescue StandardError => e
      warn "RepoBackfill failed for repo #{repo_id}: #{e.message}"
      DB.transaction do
        SetTeamContext.call(team_id)
        MonitoredRepo.where(id: repo_id).update(backfill_status: 'failed')
      end
      raise
    end

    def self.backfill_branches(repo, installation_id, default_branch)
      branches = GithubAPI.repo_branches(installation_id, repo.repo_name)
      existing_bidxs = TrackedBranch.where(monitored_repo_id: repo.id).select_map(:branch_name_bidx)
      branches.each do |branch|
        next if branch[:name] == default_branch

        bidx = BlindIndex.generate_bidx(branch[:name], key: Lockbox.master_key)
        next if existing_bidxs.include?(bidx)

        sha = branch.dig(:commit, :sha)
        commit_time = GithubAPI.commit_date(installation_id, repo.repo_name, sha)
        next unless commit_time

        TrackedBranch.create(
          monitored_repo_id: repo.id,
          branch_name:       branch[:name],
          head_sha:          sha,
          status:            'open',
          created_at:        commit_time
        )
      end

      backfill_events(repo, installation_id, default_branch)
    end

    def self.backfill_events(repo, installation_id, default_branch)
      since = Time.now - (84 * 24 * 3600)
      backfill_pushes(repo, installation_id, default_branch, since)
      backfill_merges(repo, installation_id, since)
    end

    def self.backfill_pushes(repo, installation_id, default_branch, since)
      commits = GithubAPI.default_branch_commits(
        installation_id, repo.repo_name, default_branch, since: since
      )
      commits.each do |c|
        IntegrationEvent.create(
          monitored_repo_id: repo.id, event_type: 'push', occurred_at: c[:date]
        )
      end

      MonitoredRepo.where(id: repo.id).update(last_push_at: commits.first[:date]) if commits.any?
    end

    def self.backfill_merges(repo, installation_id, since)
      pulls = GithubAPI.merged_pulls(
        installation_id, repo.repo_name, since: since
      )
      pulls.each do |pr|
        branch = find_tracked_branch(repo, pr[:branch])
        if branch && branch.status != 'merged'
          was_spike = branch.status == 'spike'
          branch.update(status: 'merged', merged_at: pr[:merged_at], merged_from_spike: was_spike)
        end
        IntegrationEvent.create(
          monitored_repo_id: repo.id, event_type: 'merge',
          occurred_at: pr[:merged_at], tracked_branch_id: branch&.id
        )
      end
    end

    def self.find_tracked_branch(repo, branch_name)
      bidx = BlindIndex.generate_bidx(branch_name, key: Lockbox.master_key)
      TrackedBranch.where(monitored_repo_id: repo.id, branch_name_bidx: bidx).first
    end

    private_class_method :backfill_branches, :backfill_events, :backfill_pushes, :backfill_merges,
      :find_tracked_branch
  end
end
