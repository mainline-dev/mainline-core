# frozen_string_literal: true

require 'sidekiq'

class RepoBackfillJob
  include Sidekiq::Job

  sidekiq_options retry: 3, queue: 'default'

  def perform(repo_id, team_id, installation_id, default_branch)
    CIMonitor::RepoBackfill.call(
      repo_id:         repo_id,
      team_id:         team_id,
      installation_id: installation_id,
      default_branch:  default_branch
    )
  end
end
