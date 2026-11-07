# frozen_string_literal: true

require 'tzinfo'
require_relative 'branch_age'

module CIMonitor
  module StreakStrip
    DAYS = 84
    METRICS_DAYS = 30

    def self.for_repo(repo_id, timezone, holiday_region: nil)
      tz = TZInfo::Timezone.get(timezone)
      today = tz.utc_to_local(Time.now.utc).to_date
      start_date = today - (DAYS - 1)

      events = window_events(repo_id, start_date)
      all_branches = window_branches(repo_id, start_date)
      days = build_days(start_date..today, events, tz, timezone, holiday_region)
      mark_branch_open_days(days, all_branches, tz)

      { days: days, streak: compute_streak(days),
        green_days: days.count { |d| !d[:weekend] && d[:score] >= 0.5 },
        total_pushes: events.count { |e| e.event_type == 'push' },
        total_merges: events.count { |e| e.event_type == 'merge' } }
        .merge(branch_metrics(all_branches, today - METRICS_DAYS, timezone, holiday_region))
    end

    def self.combine(repo_results, mode: 'average')
      return { days: [], streak: 0, green_days: 0 } if repo_results.empty?

      first_active = repo_results.map { |r|
        r[:days].index { |d| !d[:weekend] && d[:score]&.positive? }
      }
      days = repo_results.first[:days].each_index.map { |i| combined_day(repo_results, first_active, i, mode) }

      { days: days, streak: compute_streak(days),
        green_days: days.count { |d| !d[:weekend] && d[:intensity] >= 0.5 } }
    end

    def self.combined_day(repo_results, first_active, index, mode)
      day = repo_results.first[:days][index]
      intensities = repo_results.each_index
        .select { |ri| first_active[ri] && first_active[ri] <= index }
        .map { |ri| repo_results[ri][:days][index][:intensity] }

      value = if intensities.empty?
                0.0
              elsif mode == 'average'
                intensities.sum / intensities.size.to_f
              else
                intensities.max
              end
      { date: day[:date], weekend: day[:weekend], intensity: value }
    end

    def self.window_events(repo_id, start_date)
      IntegrationEvent.where(monitored_repo_id: repo_id)
        .where { occurred_at >= Sequel.cast(start_date.to_s, 'timestamptz') }
        .all
    end

    def self.window_branches(repo_id, start_date)
      start_ts = Sequel.cast(start_date.to_s, 'timestamptz')
      TrackedBranch.where(monitored_repo_id: repo_id)
        .where {
          (created_at >= start_ts) |
            Sequel.expr(status: %w[open spike]) |
            (merged_at >= start_ts) |
            (abandoned_at >= start_ts)
        }
        .all
    end

    def self.build_days(date_range, events, zone, timezone, holiday_region)
      branch_ids = events.select(&:tracked_branch_id).map(&:tracked_branch_id).uniq
      scoring = {
        branches_by_id: branch_ids.empty? ? {} : TrackedBranch.where(id: branch_ids).to_h { |b| [b.id, b] },
        timezone:       timezone,
        holiday_region: holiday_region
      }
      holidays = BranchAge.load_holidays(date_range.first, date_range.last, holiday_region)
      events_by_date = events.group_by { |e| local_date(e.occurred_at, zone) }

      days = date_range.map { |date| build_day(date, events_by_date[date] || [], holidays, scoring) }
      apply_intensity(days)
    end

    def self.build_day(date, events, holidays, scoring)
      push_count = events.count { |e| e.event_type == 'push' }
      non_working = [0, 6].include?(date.wday) || holidays.include?(date)

      { date: date, weekend: non_working,
        score: non_working ? nil : day_score(events, push_count, scoring),
        push_count: push_count, merge_count: events.count { |e| e.event_type == 'merge' },
        intensity: 0.0 }
    end

    # A day with activity scores 1.0 unless its only activity is merging stale
    # branches; then it drops toward a 0.2 floor by the worst branch age.
    def self.day_score(events, push_count, scoring)
      return 0.0 if events.empty?

      merge_events = events.select { |e| e.event_type == 'merge' }
      linked_merges = merge_events.select(&:tracked_branch_id)
      stale_ages = merge_events.filter_map { |e| stale_age(e, scoring) }
      return 1.0 unless stale_ages.any? && !push_count.positive? && stale_ages.size == linked_merges.size

      [0.2, 0.5 - ((stale_ages.max - 24) / 240.0)].max
    end

    def self.stale_age(event, scoring)
      branch = scoring[:branches_by_id][event.tracked_branch_id]
      return nil unless branch&.created_at && branch.merged_at

      age = BranchAge.hours(branch.created_at, branch.merged_at, scoring[:timezone],
        holiday_region: scoring[:holiday_region])
      age > 24 ? age : nil
    end

    def self.apply_intensity(days)
      days.each do |day|
        day[:intensity] = day[:weekend] ? 0.0 : day[:score]
      end
    end

    def self.mark_branch_open_days(days, branches, timezone)
      days.each { |d| d[:branch_open] = false }
      branches.each do |branch|
        opened, closed = branch_span(branch, timezone)
        mark_open(days, opened, closed)
      end
      days.each do |d|
        d[:intensity] = 0.15 if d[:branch_open] && !d[:intensity].positive?
      end
    end

    def self.branch_span(branch, timezone)
      closed_at = branch.merged_at || branch.abandoned_at
      [local_date(branch.created_at, timezone), closed_at && local_date(closed_at, timezone)]
    end

    def self.mark_open(days, opened, closed)
      days.each do |d|
        next if d[:weekend]
        next if d[:date] < opened

        break if closed && d[:date] > closed

        d[:branch_open] = true
      end
    end

    def self.local_date(time, timezone)
      timezone.utc_to_local(time.utc).to_date
    end

    def self.branch_metrics(branches, merge_cutoff, timezone, holiday_region)
      merged = branches.select { |b|
        b.merged_at && b.created_at && b.merged_at.to_date >= merge_cutoff && !b.merged_from_spike
      }
      ages = merged.map { |b| BranchAge.hours(b.created_at, b.merged_at, timezone, holiday_region: holiday_region) }

      { branches_over_24h: ages.count { |a| a > 24 }, p90_branch_hours: p90(ages), merge_ages: ages }
    end

    def self.p90(values)
      return nil if values.empty?

      sorted = values.sort
      sorted[(sorted.size * 0.9).ceil - 1]
    end

    def self.compute_streak(days)
      active_days = days.reject { |d| d[:weekend] }
      streak = 0
      active_days.reverse_each do |d|
        break unless d[:intensity] >= 0.5

        streak += 1
      end
      streak
    end

    private_class_method :combined_day, :window_events, :window_branches, :build_days, :build_day,
      :day_score, :stale_age, :apply_intensity, :mark_branch_open_days, :branch_span, :mark_open,
      :local_date, :branch_metrics, :p90, :compute_streak
  end
end
