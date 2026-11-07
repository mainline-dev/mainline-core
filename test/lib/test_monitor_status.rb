# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/ci_monitor/branch_age'
require_relative '../../lib/ci_monitor/status'

FakeRepo = Struct.new(:threshold_hours, :last_push_at)
FakeBranch = Struct.new(:created_at)

describe CIMonitor::Status do
  cover 'CIMonitor::Status*'

  before do
    @now = Time.utc(2026, 5, 5, 12, 0, 0) # Tuesday noon
  end

  def make_repo(threshold_hours: 24, last_push_at: Time.utc(2026, 5, 5, 10, 0, 0))
    FakeRepo.new(threshold_hours, last_push_at)
  end

  def make_branch(created_at)
    FakeBranch.new(created_at)
  end

  it 'returns green when no open branches and recent push' do
    repo = make_repo(last_push_at: Time.utc(2026, 5, 5, 10, 0, 0))

    result = CIMonitor::Status.for_repo(repo, [], 'UTC', now: @now)

    assert_equal :green, result
  end

  it 'returns amber when no open branches and no push ever' do
    repo = make_repo(last_push_at: nil)

    result = CIMonitor::Status.for_repo(repo, [], 'UTC', now: @now)

    assert_equal :amber, result
  end

  it 'returns amber when no open branches and stale push' do
    repo = make_repo(last_push_at: Time.utc(2026, 5, 1, 9, 0, 0)) # Thursday 9am

    result = CIMonitor::Status.for_repo(repo, [], 'UTC', now: @now)

    assert_equal :amber, result
  end

  it 'returns green when branches are within threshold' do
    repo = make_repo(threshold_hours: 24)
    branches = [make_branch(Time.utc(2026, 5, 5, 0, 0, 0))] # 12h old

    result = CIMonitor::Status.for_repo(repo, branches, 'UTC', now: @now)

    assert_equal :green, result
  end

  it 'returns red when any branch exceeds threshold' do
    repo = make_repo(threshold_hours: 24)
    branches = [
      make_branch(Time.utc(2026, 5, 5, 0, 0, 0)), # 12h - ok
      make_branch(Time.utc(2026, 5, 2, 12, 0, 0)) # Saturday noon to Tuesday noon = 36h weekday
    ]

    result = CIMonitor::Status.for_repo(repo, branches, 'UTC', now: @now)

    assert_equal :red, result
  end

  it 'red takes priority over amber' do
    repo = make_repo(threshold_hours: 24, last_push_at: nil)
    branches = [make_branch(Time.utc(2026, 5, 2, 12, 0, 0))]

    result = CIMonitor::Status.for_repo(repo, branches, 'UTC', now: @now)

    assert_equal :red, result
  end

  it 'push staleness uses fixed 24h window regardless of goal' do
    repo = make_repo(last_push_at: Time.utc(2026, 5, 4, 10, 0, 0)) # Monday 10am, 26 weekday hours ago

    result = CIMonitor::Status.for_repo(repo, [], 'UTC', now: @now)

    assert_equal :amber, result
  end

  it 'only considers branches in open_branches for red' do
    repo = make_repo(threshold_hours: 8)
    old_branch = make_branch(Time.utc(2026, 5, 2, 12, 0, 0))

    with_old = CIMonitor::Status.for_repo(repo, [old_branch], 'UTC', now: @now)
    without = CIMonitor::Status.for_repo(repo, [], 'UTC', now: @now)

    assert_equal :red, with_old
    assert_equal :green, without
  end

  describe '.overall' do
    it 'returns green when all repos green' do
      assert_equal :green, CIMonitor::Status.overall([:green, :green])
    end

    it 'returns red when any repo is red' do
      assert_equal :red, CIMonitor::Status.overall([:green, :red, :amber])
    end

    it 'returns amber when worst is amber' do
      assert_equal :amber, CIMonitor::Status.overall([:green, :amber])
    end

    it 'returns none for empty list' do
      assert_equal :none, CIMonitor::Status.overall([])
    end
  end
end
