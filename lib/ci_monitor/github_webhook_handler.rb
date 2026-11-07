# frozen_string_literal: true

module CIMonitor
  class GithubWebhookHandler
    def initialize(event, payload)
      @event = event
      @payload = payload
    end

    def call
      return handle_installation_removed if installation_removed?

      repos = find_repos
      repos.each { |repo| handle_repo_event(repo) }
    end

    private

    def handle_repo_event(repo)
      sync_repo_name(repo)
      case @event
      when 'create'       then handle_branch_create(repo)
      when 'delete'       then handle_branch_delete(repo)
      when 'push'         then handle_push(repo)
      when 'pull_request' then handle_pull_request(repo)
      end
    end

    def sync_repo_name(repo)
      current_name = @payload.dig(:repository, :full_name)
      return unless current_name

      bidx = BlindIndex.generate_bidx(current_name, key: Lockbox.master_key)
      return if repo.repo_name_bidx == bidx

      box = Lockbox.new(key: Lockbox.master_key, encode: true)
      repo.update(
        repo_name_ciphertext: box.encrypt(current_name),
        repo_name_bidx:       bidx
      )
    end

    def find_repos
      installation_id = @payload.dig(:installation, :id)
      repo_id = @payload.dig(:repository, :id)
      return [] unless installation_id && repo_id

      MonitoredRepo.where(
        provider_installation_id: installation_id,
        provider_repo_id:         repo_id
      ).all
    end

    def handle_branch_create(repo)
      return unless @payload[:ref_type] == 'branch'
      return if @payload[:ref] == repo.default_branch

      bidx = BlindIndex.generate_bidx(@payload[:ref], key: Lockbox.master_key)
      existing = TrackedBranch.where(
        monitored_repo_id: repo.id, branch_name_bidx: bidx
      ).where(status: %w[open spike]).first
      return if existing

      TrackedBranch.create(
        monitored_repo_id: repo.id,
        branch_name:       @payload[:ref],
        status:            'open'
      )
    end

    def handle_branch_delete(repo)
      return unless @payload[:ref_type] == 'branch'

      bidx = BlindIndex.generate_bidx(@payload[:ref], key: Lockbox.master_key)
      branch = TrackedBranch.where(
        monitored_repo_id: repo.id, branch_name_bidx: bidx
      ).where(status: %w[open spike]).first
      return unless branch

      branch.update(status: 'abandoned', abandoned_at: Time.now)
    end

    def handle_pull_request(repo)
      return unless @payload[:action] == 'closed'
      return unless @payload.dig(:pull_request, :merged)

      ref = @payload.dig(:pull_request, :head, :ref)
      return unless ref

      bidx = BlindIndex.generate_bidx(ref, key: Lockbox.master_key)
      branch = TrackedBranch.where(
        monitored_repo_id: repo.id, branch_name_bidx: bidx
      ).where(status: %w[open spike abandoned]).first
      return unless branch

      raw = @payload.dig(:pull_request, :merged_at)
      merged_at = raw ? Time.parse(raw.to_s) : Time.now
      was_spike = branch.status == 'spike'
      branch.update(status: 'merged', merged_at: merged_at, merged_from_spike: was_spike)
      IntegrationEvent.create(
        monitored_repo_id: repo.id, event_type: 'merge',
        occurred_at: merged_at, tracked_branch_id: branch.id
      )
    end

    def handle_push(repo)
      return unless @payload[:ref] == "refs/heads/#{repo.default_branch}"

      now = Time.now
      repo.update(last_push_at: now)
      IntegrationEvent.create(
        monitored_repo_id: repo.id, event_type: 'push', occurred_at: now
      )
    end

    def installation_removed?
      @event == 'installation' && %w[deleted suspended].include?(@payload[:action])
    end

    def handle_installation_removed
      installation_id = @payload.dig(:installation, :id)
      return unless installation_id

      DB.transaction do
        MonitoredRepo.where(provider_installation_id: installation_id).each do |repo|
          IntegrationEvent.where(monitored_repo_id: repo.id).delete
          TrackedBranch.where(monitored_repo_id: repo.id).delete
        end
        MonitoredRepo.where(provider_installation_id: installation_id).delete
        TeamInstallation.where(installation_id: installation_id).delete
      end
    end
  end
end
