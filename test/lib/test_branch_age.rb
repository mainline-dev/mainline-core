# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/ci_monitor/branch_age'
require 'holidays'

describe CIMonitor::BranchAge do
  cover 'CIMonitor::BranchAge*'

  it 'returns hours elapsed on same weekday' do
    created = Time.utc(2026, 5, 4, 9, 0, 0) # Monday 9am
    now = Time.utc(2026, 5, 4, 15, 0, 0)    # Monday 3pm

    assert_equal 6, CIMonitor::BranchAge.hours(created, now, 'UTC')
  end

  it 'counts hours across weekdays' do
    created = Time.utc(2026, 5, 4, 9, 0, 0) # Monday 9am
    now = Time.utc(2026, 5, 5, 9, 0, 0)     # Tuesday 9am

    assert_equal 24, CIMonitor::BranchAge.hours(created, now, 'UTC')
  end

  it 'excludes weekend hours' do
    created = Time.utc(2026, 5, 1, 9, 0, 0) # Friday 9am
    now = Time.utc(2026, 5, 4, 9, 0, 0)     # Monday 9am

    assert_equal 24, CIMonitor::BranchAge.hours(created, now, 'UTC')
  end

  it 'handles branch created on Saturday' do
    created = Time.utc(2026, 5, 2, 12, 0, 0) # Saturday noon
    now = Time.utc(2026, 5, 4, 12, 0, 0)     # Monday noon

    assert_equal 12, CIMonitor::BranchAge.hours(created, now, 'UTC')
  end

  it 'handles now on Sunday' do
    created = Time.utc(2026, 5, 1, 9, 0, 0) # Friday 9am
    now = Time.utc(2026, 5, 3, 14, 0, 0)    # Sunday 2pm

    assert_equal 15, CIMonitor::BranchAge.hours(created, now, 'UTC')
  end

  it 'respects timezone' do
    created = Time.utc(2026, 5, 3, 14, 0, 0) # Sun 14:00 UTC = Mon 0:00 AEST
    now = Time.utc(2026, 5, 4, 14, 0, 0)     # Mon 14:00 UTC = Tue 0:00 AEST

    assert_equal 24, CIMonitor::BranchAge.hours(created, now, 'Australia/Sydney')
  end

  it 'returns 0 when created and now are same time' do
    t = Time.utc(2026, 5, 5, 10, 0, 0)

    assert_equal 0, CIMonitor::BranchAge.hours(t, t, 'UTC')
  end

  it 'timezone shifts weekend boundary' do
    created = Time.utc(2026, 5, 1, 10, 0, 0) # Fri 10:00 UTC = Fri 20:00 AEST
    now = Time.utc(2026, 5, 1, 20, 0, 0)     # Fri 20:00 UTC = Sat 06:00 AEST

    assert_equal 10, CIMonitor::BranchAge.hours(created, now, 'UTC')
    assert_equal 4, CIMonitor::BranchAge.hours(created, now, 'Australia/Sydney')
  end

  it 'handles DST spring-forward correctly' do
    # US DST 2026: clocks spring forward Sun Mar 8 at 2am
    # Friday before -> Monday after
    created = Time.utc(2026, 3, 6, 14, 0, 0)  # Fri 9am EST (UTC-5)
    now = Time.utc(2026, 3, 9, 13, 0, 0)      # Mon 9am EDT (UTC-4)

    assert_equal 24, CIMonitor::BranchAge.hours(created, now, 'America/New_York')
  end

  it 'handles DST fall-back correctly' do
    # US DST 2026: clocks fall back Sun Nov 1 at 2am
    # Friday before -> Monday after
    created = Time.utc(2026, 10, 30, 13, 0, 0) # Fri 9am EDT (UTC-4)
    now = Time.utc(2026, 11, 2, 14, 0, 0)      # Mon 9am EST (UTC-5)

    assert_equal 24, CIMonitor::BranchAge.hours(created, now, 'America/New_York')
  end

  it 'spans multiple weekends' do
    created = Time.utc(2026, 5, 4, 9, 0, 0)  # Monday 9am
    now = Time.utc(2026, 5, 18, 9, 0, 0)     # Monday 9am, 2 weeks later

    assert_equal 240, CIMonitor::BranchAge.hours(created, now, 'UTC')
  end

  it 'does not crash when DST springs forward at midnight' do
    # Cuba 2026-03-08: clocks jump 00:00 -> 01:00 (midnight is invalid local time)
    # Branch created Friday 5pm Cuba, now Monday 9am Cuba
    created = Time.utc(2026, 3, 6, 22, 0, 0)  # Fri 17:00 Cuba (UTC-5)
    now = Time.utc(2026, 3, 9, 13, 0, 0)      # Mon 09:00 Cuba (UTC-4, post DST)

    result = CIMonitor::BranchAge.hours(created, now, 'America/Havana')

    assert_equal 16, result # 7h Friday + 9h Monday
  end

  it 'excludes public holidays when region is set' do
    # Australia Day 2026 is Mon Jan 26
    created = Time.utc(2026, 1, 23, 0, 0, 0) # Friday midnight UTC
    now = Time.utc(2026, 1, 27, 0, 0, 0)     # Tuesday midnight UTC

    without_holidays = CIMonitor::BranchAge.hours(created, now, 'UTC')
    with_holidays = CIMonitor::BranchAge.hours(created, now, 'UTC', holiday_region: 'au')

    assert_equal 48, without_holidays  # Fri + Mon = 48h
    assert_equal 24, with_holidays     # Fri only, Mon is holiday = 24h
  end

  it 'does not exclude holidays when region is nil' do
    created = Time.utc(2026, 1, 23, 0, 0, 0)
    now = Time.utc(2026, 1, 27, 0, 0, 0)

    assert_equal 48, CIMonitor::BranchAge.hours(created, now, 'UTC', holiday_region: nil)
  end

  it 'excludes multi-day holidays' do
    # Christmas 2025: Thu Dec 25 + Fri Dec 26 (Boxing Day) in AU NSW
    created = Time.utc(2025, 12, 24, 0, 0, 0) # Wednesday midnight
    now = Time.utc(2025, 12, 29, 0, 0, 0)     # Monday midnight

    result = CIMonitor::BranchAge.hours(created, now, 'UTC', holiday_region: 'au_nsw')

    assert_equal 24, result # Only Wednesday counts (Thu=Xmas, Fri=Boxing, Sat+Sun=weekend)
  end
end
