# frozen_string_literal: true

require 'time'
require 'tzinfo'

module CIMonitor
  module BranchAge
    def self.hours(created_at, now, timezone, holiday_region: nil)
      tz = find_tz(timezone)
      from = tz.utc_to_local(created_at.utc)
      to = tz.utc_to_local(now.utc)
      holidays = load_holidays(from.to_date, to.to_date, holiday_region)

      total = 0.0
      cursor = from

      while cursor < to
        if working_day?(cursor, holidays)
          end_of_day = beginning_of_next_day(cursor, tz)
          chunk_end = [to, end_of_day].min
          total += (chunk_end - cursor) / 3600.0
          cursor = chunk_end
        else
          cursor = beginning_of_next_day(cursor, tz)
        end
      end

      total.round
    end

    def self.load_holidays(from_date, to_date, region)
      return Set.new unless region
      return Set.new if from_date > to_date

      require 'holidays'
      Holidays.between(from_date, to_date, region.to_sym).to_set { |h| h[:date] }
    rescue Holidays::InvalidRegion
      Set.new
    end

    def self.find_tz(name)
      TZInfo::Timezone.get(name)
    end

    def self.working_day?(time, holidays)
      time.wday.between?(1, 5) && !holidays.include?(time.to_date)
    end

    def self.beginning_of_next_day(time, timezone)
      next_date = time.to_date + 1
      local_midnight = Time.utc(next_date.year, next_date.month, next_date.day)
      utc = begin
        timezone.local_to_utc(local_midnight)
      rescue TZInfo::PeriodNotFound
        timezone.local_to_utc(local_midnight + 3600)
      end
      timezone.utc_to_local(utc)
    end

    private_class_method :find_tz, :working_day?, :beginning_of_next_day
  end
end
