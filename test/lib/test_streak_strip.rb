# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/ci_monitor/branch_age'
require_relative '../../lib/ci_monitor/streak_strip'
require 'timecop'

describe 'CIMonitor::StreakStrip' do
  before do
    @team = Team.create(name: 'StreakTest')
    SetTeamContext.call(@team.id)
    TeamInstallation.create(
      team_id: @team.id, provider: 'github', installation_id: 1, org_name: 'acme'
    )
    @repo = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 100,
      repo_name: 'acme/web', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
  end

  def recent_weekday
    d = Date.today
    d -= 1 until d.wday.between?(1, 5)
    d
  end

  def recent_saturday
    d = Date.today
    d -= 1 until d.wday == 6
    d
  end

  def push_on(date)
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'push',
      occurred_at: Time.utc(date.year, date.month, date.day, 12, 0, 0)
    )
  end

  def timely_merge_on(date, suffix = '')
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: "feat/quick#{suffix}",
      head_sha: "abc#{suffix}", status: 'merged',
      created_at: Time.utc(date.year, date.month, date.day, 8, 0, 0),
      merged_at: Time.utc(date.year, date.month, date.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: Time.utc(date.year, date.month, date.day, 14, 0, 0),
      tracked_branch_id: branch.id
    )
  end

  def stale_merge_on(date, suffix = '')
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: "feat/slow#{suffix}",
      head_sha: "def#{suffix}", status: 'merged',
      created_at: Time.utc(date.year, date.month, date.day, 8, 0, 0) - (3 * 24 * 3600),
      merged_at: Time.utc(date.year, date.month, date.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: Time.utc(date.year, date.month, date.day, 14, 0, 0),
      tracked_branch_id: branch.id
    )
  end

  it 'returns 90 days of data' do
    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_equal 84, result[:days].size
  end

  it 'scores a push day as 1.0' do
    day = recent_weekday
    push_on(day)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_in_delta 1.0, entry[:score]
  end

  it 'scores a timely merge day as 1.0' do
    day = recent_weekday
    timely_merge_on(day)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_in_delta 1.0, entry[:score]
  end

  it 'scores a stale merge day below 0.5' do
    day = recent_weekday
    stale_merge_on(day)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_operator entry[:score], :>, 0.0
    assert_operator entry[:score], :<, 0.5
  end

  it 'scores a very stale merge lower than a slightly stale merge' do
    day = recent_weekday
    prev = day - 1
    prev -= 1 until prev.wday.between?(1, 5)

    slightly_stale = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/slight',
      head_sha: 'aaa', status: 'merged',
      created_at: Time.utc(prev.year, prev.month, prev.day, 8, 0, 0) - (2 * 24 * 3600),
      merged_at: Time.utc(prev.year, prev.month, prev.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: slightly_stale.merged_at, tracked_branch_id: slightly_stale.id
    )

    very_stale = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/very',
      head_sha: 'bbb', status: 'merged',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (7 * 24 * 3600),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: very_stale.merged_at, tracked_branch_id: very_stale.id
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    slight_entry = result[:days].find { |d| d[:date] == prev }
    very_entry = result[:days].find { |d| d[:date] == day }

    assert_operator very_entry[:score], :<, slight_entry[:score],
      'longer-lived branch should score lower'
  end

  it 'does not rescue stale merge score when one merge event is unlinked' do
    day = recent_weekday
    stale_merge_on(day)
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: Time.utc(day.year, day.month, day.day, 15, 0, 0),
      tracked_branch_id: nil
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_operator entry[:score], :<, 0.5,
      'unlinked merge event should not rescue a stale merge day to 1.0'
  end

  it 'scores an idle weekday as 0.0' do
    day = recent_weekday

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_in_delta 0.0, entry[:score]
  end

  it 'skips weekends in score (nil)' do
    day = recent_saturday

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_nil entry[:score]
    assert entry[:weekend]
  end

  it 'weekends do not break streak (Fri push, skip weekend, Mon push)' do
    fri = recent_weekday
    fri -= 1 until fri.wday == 5
    mon = fri + 3

    push_on(fri)
    push_on(mon)

    fake_now = Time.utc(mon.year, mon.month, mon.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }

    assert_operator result[:streak], :>=, 2
  end

  it 'weekends do not count toward green_days' do
    sat = recent_saturday
    push_on(sat)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    sat_entry = result[:days].find { |d| d[:date] == sat }

    assert sat_entry[:weekend]
    assert_equal 0, result[:green_days]
  end

  it 'weekend activity does not inflate green_days' do
    day = recent_weekday
    sat = recent_saturday
    push_on(day)
    push_on(sat)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_equal 1, result[:green_days]
  end

  it 'weekend intensity is always 0.0 even with activity' do
    sat = recent_saturday
    push_on(sat)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    sat_entry = result[:days].find { |d| d[:date] == sat }

    assert_in_delta 0.0, sat_entry[:intensity]
  end

  it 'weekend does not affect rolling average of adjacent weekdays' do
    fri = recent_weekday
    fri -= 1 until fri.wday == 5
    mon = fri + 3

    push_on(fri)
    push_on(mon)

    fake_now = Time.utc(mon.year, mon.month, mon.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }

    fri_entry = result[:days].find { |d| d[:date] == fri }
    mon_entry = result[:days].find { |d| d[:date] == mon }

    assert_in_delta fri_entry[:intensity], mon_entry[:intensity], 0.2
  end

  it 'intensity matches the day own score without smoothing' do
    day = recent_weekday
    push_on(day)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_in_delta 1.0, entry[:intensity], 0.01
  end

  it 'gap day does not dim adjacent days' do
    day = recent_weekday
    day -= 1 until day.wday == 3

    push_on(day - 2)
    push_on(day)

    fake_now = Time.utc(day.year, day.month, day.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }

    mon_entry = result[:days].find { |d| d[:date] == day - 2 }
    wed_entry = result[:days].find { |d| d[:date] == day }

    assert_in_delta 1.0, mon_entry[:intensity], 0.01
    assert_in_delta 1.0, wed_entry[:intensity], 0.01
  end

  it 'idle day intensity is 0.0 regardless of neighbours' do
    day = recent_weekday
    day -= 1 until day.wday == 3

    push_on(day - 2)
    push_on(day)

    fake_now = Time.utc(day.year, day.month, day.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }

    tue_entry = result[:days].find { |d| d[:date] == day - 1 }

    assert_in_delta 0.0, tue_entry[:intensity], 0.01
  end

  it 'includes push and merge counts for tooltips' do
    day = recent_weekday
    push_on(day)
    push_on(day)
    timely_merge_on(day)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_equal 2, entry[:push_count]
    assert_equal 1, entry[:merge_count]
  end

  it 'computes streak as consecutive weekdays with score > 0' do
    day = recent_weekday
    5.times do |i|
      d = day - i
      next unless d.wday.between?(1, 5)

      push_on(d)
    end

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_operator result[:streak], :>=, 3
  end

  it 'combine does not dim active repo when another repo has no activity yet' do
    repo2 = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 200,
      repo_name: 'acme/api', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
    day = recent_weekday
    push_on(day)

    r1 = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    r2 = CIMonitor::StreakStrip.for_repo(repo2.id, 'UTC')
    combined = CIMonitor::StreakStrip.combine([r1, r2])

    entry = combined[:days].find { |d| d[:date] == day }
    r1_entry = r1[:days].find { |d| d[:date] == day }

    assert_in_delta r1_entry[:intensity], entry[:intensity], 0.01
  end

  it 'respects team timezone for day boundaries' do
    Timecop.freeze(Time.utc(2026, 1, 8, 12, 0, 0)) do
      day = Date.new(2026, 1, 7)

      IntegrationEvent.create(
        monitored_repo_id: @repo.id, event_type: 'push',
        occurred_at: Time.utc(day.year, day.month, day.day, 23, 30, 0)
      )

      result_utc = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
      result_tokyo = CIMonitor::StreakStrip.for_repo(@repo.id, 'Asia/Tokyo')

      utc_entry = result_utc[:days].find { |d| d[:date] == day }
      tokyo_entry = result_tokyo[:days].find { |d| d[:date] == day + 1 }

      assert_in_delta 1.0, utc_entry[:score]
      assert_in_delta 1.0, tokyo_entry[:score]
    end
  end

  it 'combine returns consistent day shape for single and multiple repos' do
    repo2 = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 202,
      repo_name: 'acme/lib', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
    day = recent_weekday
    push_on(day)

    r1 = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    r2 = CIMonitor::StreakStrip.for_repo(repo2.id, 'UTC')

    single = CIMonitor::StreakStrip.combine([r1])
    multi = CIMonitor::StreakStrip.combine([r1, r2])

    single_keys = single[:days].first.keys.sort
    multi_keys = multi[:days].first.keys.sort

    assert_equal multi_keys, single_keys
  end

  it 'combine returns streak and green_days for single repo' do
    day = recent_weekday
    push_on(day)

    r1 = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    combined = CIMonitor::StreakStrip.combine([r1])

    assert combined.key?(:streak)
    assert combined.key?(:green_days)
    assert combined.key?(:days)
  end

  it 'combine returns streak and green_days for multiple repos' do
    repo2 = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 201,
      repo_name: 'acme/web', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )
    day = recent_weekday
    push_on(day)

    r1 = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    r2 = CIMonitor::StreakStrip.for_repo(repo2.id, 'UTC')
    combined = CIMonitor::StreakStrip.combine([r1, r2])

    assert combined.key?(:streak)
    assert combined.key?(:green_days)
    assert combined.key?(:days)
  end

  it 'combine uses max not average so idle repo does not drag down active repo' do
    repo2 = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 203,
      repo_name: 'acme/idle', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )

    today = recent_weekday
    early = today - 30
    early -= 1 until early.wday.between?(1, 5)

    IntegrationEvent.create(
      monitored_repo_id: repo2.id, event_type: 'push',
      occurred_at: Time.utc(early.year, early.month, early.day, 12, 0, 0)
    )
    push_on(today)

    r1 = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    r2 = CIMonitor::StreakStrip.for_repo(repo2.id, 'UTC')
    combined = CIMonitor::StreakStrip.combine([r1, r2], mode: 'max')

    r1_entry = r1[:days].find { |d| d[:date] == today }
    combined_entry = combined[:days].find { |d| d[:date] == today }

    assert_in_delta r1_entry[:intensity], combined_entry[:intensity], 0.01,
      'idle repo should not drag down the combined bar'
  end

  it 'combine defaults to average mode' do
    repo2 = MonitoredRepo.create(
      team_id: @team.id, provider_installation_id: 1, provider_repo_id: 204,
      repo_name: 'acme/avg', default_branch: 'main',
      threshold_hours: 24, last_push_at: Time.now
    )

    today = recent_weekday
    early = today - 30
    early -= 1 until early.wday.between?(1, 5)

    IntegrationEvent.create(
      monitored_repo_id: repo2.id, event_type: 'push',
      occurred_at: Time.utc(early.year, early.month, early.day, 12, 0, 0)
    )
    push_on(today)

    r1 = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    r2 = CIMonitor::StreakStrip.for_repo(repo2.id, 'UTC')
    combined = CIMonitor::StreakStrip.combine([r1, r2], mode: 'average')

    r1_entry = r1[:days].find { |d| d[:date] == today }
    combined_entry = combined[:days].find { |d| d[:date] == today }

    assert_operator combined_entry[:intensity], :<, r1_entry[:intensity],
      'average mode should dilute when one repo is idle'
  end

  it 'marks days when a branch was sitting open' do
    day = recent_weekday
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/long',
      head_sha: 'abc', status: 'open',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (2 * 24 * 3600)
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert entry[:branch_open], 'day should be marked as having an open branch'
    assert_in_delta 0.15, entry[:intensity], 0.001, 'branch-open day with no activity should have intensity 0.15'
  end

  it 'does not override intensity when branch is open and activity exists' do
    day = recent_weekday
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/active',
      head_sha: 'abc', status: 'open',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (2 * 24 * 3600)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'push',
      occurred_at: Time.utc(day.year, day.month, day.day, 10, 0, 0)
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert entry[:branch_open], 'day should be marked as having an open branch'
    assert_in_delta 1.0, entry[:intensity], 0.001, 'activity should keep full intensity even when branch is open'
  end

  it 'scores stale merge day with open branch as active not gap' do
    day = recent_weekday
    day -= 1 until day.wday == 5
    merge_day = day - 2

    stale_branch = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/stale',
      head_sha: 'abc', status: 'merged',
      created_at: Time.utc(merge_day.year, merge_day.month, merge_day.day, 8, 0, 0) - (3 * 24 * 3600),
      merged_at: Time.utc(merge_day.year, merge_day.month, merge_day.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: stale_branch.merged_at, tracked_branch_id: stale_branch.id
    )
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/sitting',
      head_sha: 'def', status: 'open',
      created_at: Time.utc(merge_day.year, merge_day.month, merge_day.day, 6, 0, 0)
    )

    fake_now = Time.utc(day.year, day.month, day.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }
    entry = result[:days].find { |d| d[:date] == merge_day }

    assert entry[:branch_open], 'day should have branch_open set'
    assert_operator entry[:score], :>, 0, 'stale merge should still produce a positive score'
    assert_operator entry[:intensity], :>, 0, 'intensity should be positive so the bar is visible'
  end

  it 'does not mark branch_open on days before branch was created' do
    day = recent_weekday
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/new',
      head_sha: 'abc', status: 'open',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0)
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    yesterday = result[:days].find { |d| d[:date] == day - 1 }

    refute yesterday[:branch_open], 'day before branch creation should not be marked'
  end

  it 'stops marking branch_open after branch is merged' do
    day = recent_weekday
    day -= 1 until day.wday == 5
    mon = day - 4
    wed = mon + 2

    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/done',
      head_sha: 'abc', status: 'merged',
      created_at: Time.utc(mon.year, mon.month, mon.day, 8, 0, 0),
      merged_at: Time.utc(wed.year, wed.month, wed.day, 14, 0, 0)
    )

    fake_now = Time.utc(day.year, day.month, day.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }

    fri_entry = result[:days].find { |d| d[:date] == day }

    refute fri_entry[:branch_open], 'day after merge should not be marked'
  end

  it 'returns total push and merge counts' do
    day = recent_weekday
    push_on(day)
    push_on(day)
    timely_merge_on(day)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_equal 2, result[:total_pushes]
    assert_equal 1, result[:total_merges]
  end

  it 'returns branches_over_24h count for merged branches' do
    day = recent_weekday
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/quick',
      head_sha: 'aaa', status: 'merged',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/slow',
      head_sha: 'bbb', status: 'merged',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (3 * 24 * 3600),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_equal 1, result[:branches_over_24h]
  end

  it 'returns p90_branch_hours for merged branches' do
    day = recent_weekday
    day -= 1 until day.wday == 5

    5.times do |i|
      TrackedBranch.create(
        monitored_repo_id: @repo.id, branch_name: "feat/quick-#{i}",
        head_sha: "q#{i}", status: 'merged',
        created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0),
        merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
      )
    end
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/slow',
      head_sha: 'sss', status: 'merged',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (5 * 24 * 3600),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )

    fake_now = Time.utc(day.year, day.month, day.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }

    assert_operator result[:p90_branch_hours], :>, 24,
      'P90 should reflect the slow branch'
  end

  it 'returns zero counts when no merged branches exist' do
    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_equal 0, result[:branches_over_24h]
    assert_nil result[:p90_branch_hours]
  end

  it 'push on same day as stale merge redeems the score to 1.0' do
    day = recent_weekday
    stale_merge_on(day)
    push_on(day)

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_in_delta 1.0, entry[:score]
  end

  it 'very ancient branch hits the 0.2 score floor' do
    day = recent_weekday
    branch = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/ancient',
      head_sha: 'zzz', status: 'merged',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (30 * 24 * 3600),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: branch.merged_at, tracked_branch_id: branch.id
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert_in_delta 0.2, entry[:score], 0.01
  end

  it 'multiple stale merges on same day penalizes by worst age' do
    day = recent_weekday
    day -= 1 until day.wday == 5

    b1 = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/medium',
      head_sha: 'mmm', status: 'merged',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (3 * 24 * 3600),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: b1.merged_at, tracked_branch_id: b1.id
    )
    b2 = TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/old',
      head_sha: 'ooo', status: 'merged',
      created_at: Time.utc(day.year, day.month, day.day, 8, 0, 0) - (14 * 24 * 3600),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )
    IntegrationEvent.create(
      monitored_repo_id: @repo.id, event_type: 'merge',
      occurred_at: b2.merged_at, tracked_branch_id: b2.id
    )

    fake_now = Time.utc(day.year, day.month, day.day, 18, 0, 0)
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    }
    entry = result[:days].find { |d| d[:date] == day }

    assert_operator entry[:score], :<, 0.5, 'should use worst (oldest) branch age'
    assert_operator entry[:score], :>=, 0.2, 'should not go below the floor'
  end

  it 'compute_streak uses intensity as source of truth' do
    days = [
      { date: Date.today - 1, weekend: false, score: 0.0, intensity: 0.8 },
      { date: Date.today, weekend: false, score: 0.0, intensity: 0.6 }
    ]
    streak = CIMonitor::StreakStrip.send(:compute_streak, days)

    assert_equal 2, streak, 'streak should count days by intensity, not score'
  end

  it 'combine returns empty result for empty input' do
    combined = CIMonitor::StreakStrip.combine([])

    assert_equal [], combined[:days]
    assert_equal 0, combined[:streak]
    assert_equal 0, combined[:green_days]
  end

  it 'combine green_days excludes stale-merge-only days' do
    day = recent_weekday
    stale_merge_on(day)

    r1 = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    combined = CIMonitor::StreakStrip.combine([r1])

    r1_entry = r1[:days].find { |d| d[:date] == day }

    assert_operator r1_entry[:intensity], :>, 0.0, 'stale merge should have some intensity'
    assert_operator r1_entry[:intensity], :<, 0.5, 'stale merge intensity should be below 0.5'
    assert_equal r1[:green_days], combined[:green_days],
      'combine green_days should match per-repo green_days'
  end

  it 'marks branch_open for branches created before the 84-day window' do
    day = recent_weekday
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/ancient-open',
      head_sha: 'old', status: 'open',
      created_at: Time.now - (100 * 24 * 3600)
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')
    entry = result[:days].find { |d| d[:date] == day }

    assert entry[:branch_open], 'old open branch should still mark days as branch_open'
  end

  it 'counts old branches merged within window in branches_over_24h' do
    day = recent_weekday
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/old-merged',
      head_sha: 'om', status: 'merged',
      created_at: Time.now - (100 * 24 * 3600),
      merged_at: Time.utc(day.year, day.month, day.day, 14, 0, 0)
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_equal 1, result[:branches_over_24h],
      'branch merged within window should count even if created before window'
  end

  it 'branch metrics use 30-day window not full 84 days' do
    TrackedBranch.create(
      monitored_repo_id: @repo.id, branch_name: 'feat/old-stale',
      head_sha: 'os', status: 'merged',
      created_at: Time.now - (50 * 24 * 3600),
      merged_at: Time.now - (45 * 24 * 3600)
    )

    result = CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC')

    assert_equal 0, result[:branches_over_24h],
      'branch merged 45 days ago should not count in 30-day window'
    assert_nil result[:p90_branch_hours],
      'no recent merges means nil P90'
  end

  it 'excludes public holidays from streak count' do
    # Australia Day 2026 is Mon Jan 26 - no events on holiday
    # Push on Fri Jan 23 and Tue Jan 27 - streak should not break
    fri = Date.new(2026, 1, 23)
    tue = Date.new(2026, 1, 27)

    [fri, tue].each do |d|
      IntegrationEvent.create(
        monitored_repo_id: @repo.id, event_type: 'push',
        occurred_at: Time.utc(d.year, d.month, d.day, 12, 0, 0)
      )
    end

    fake_now = Time.utc(2026, 1, 27, 18, 0, 0) # Tue Jan 27 evening
    result = Time.stub(:now, fake_now) {
      CIMonitor::StreakStrip.for_repo(@repo.id, 'UTC', holiday_region: 'au')
    }

    mon_entry = result[:days].find { |d| d[:date] == Date.new(2026, 1, 26) }

    assert mon_entry[:weekend], 'holiday should be marked as non-working'
    assert_operator result[:streak], :>=, 2, 'streak should not break over holiday'
  end
end
