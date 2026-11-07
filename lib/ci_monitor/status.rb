# frozen_string_literal: true

module CIMonitor
  module Status
    PUSH_STALENESS_HOURS = 24

    def self.for_repo(repo, open_branches, timezone, now: Time.now, holiday_region: nil)
      over_threshold = open_branches.any? { |branch|
        BranchAge.hours(branch.created_at, now, timezone, holiday_region: holiday_region) > repo.threshold_hours
      }

      return :red if over_threshold

      push_stale = repo.last_push_at.nil? ||
                   BranchAge.hours(repo.last_push_at, now, timezone, holiday_region: holiday_region) > PUSH_STALENESS_HOURS

      push_stale ? :amber : :green
    end

    def self.overall(statuses)
      return :none if statuses.empty?
      return :red if statuses.include?(:red)
      return :amber if statuses.include?(:amber)

      :green
    end
  end
end
