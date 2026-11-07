# frozen_string_literal: true

require_relative '../model_spec_helper'
require 'sidekiq'
require 'sidekiq/testing'
require_relative '../../lib/jobs/let_go_job'

describe LetGoJob do
  before do
    Sidekiq::Testing.fake!
    Sidekiq::Queues.clear_all
  end

  after do
    Sidekiq::Testing.disable!
  end

  def untouched_exhibit(team)
    BypassRLS.call do
      MuseumItem.create(team_id: team.id, source_key: 'SHOP-1', issue_type: 'Story', summary: 'Gift cards at the till',
        source_created_at: Time.now - (2 * 365 * 24 * 60 * 60))
    end
  end

  def group(item)
    BypassRLS.call { item.refresh.let_go_group }
  end

  it "looks for exhibits to let go in every team's museum each night" do
    exhibits = [untouched_exhibit(Team.create(name: 'Acme')), untouched_exhibit(Team.create(name: 'Other'))]

    LetGoJob.new.perform
    groups = exhibits.map { |item| group(item) }

    assert_equal %w[stale stale], groups
  end

  it 'keeps going when one museum fails, and still comes back the next night' do
    broken = Team.create(name: 'Acme')
    fine = untouched_exhibit(Team.create(name: 'Other'))
    detect = LetGo.method(:detect)
    failing = lambda { |team_id:|
      raise Sequel::DatabaseError, 'boom' if team_id == broken.id

      detect.call(team_id: team_id)
    }
    untouched_exhibit(broken)

    LetGo.stub(:detect, failing) { LetGoJob.new.perform }

    assert_equal 'stale', group(fine)
    assert_equal 1, LetGoJob.jobs.size
  end

  it 're-enqueues itself for the next night' do
    LetGoJob.new.perform

    assert_equal 1, LetGoJob.jobs.size
    assert_in_delta LetGoJob::INTERVAL, LetGoJob.jobs.first['at'] - Time.now.to_f, 60
  end

  it "looks in one team's museum after an acquisition, once" do
    team = Team.create(name: 'Acme')
    mine = untouched_exhibit(team)
    theirs = untouched_exhibit(Team.create(name: 'Other'))

    LetGoJob.new.perform(team.id)

    assert_equal ['stale', nil], [group(mine), group(theirs)]
    assert_empty LetGoJob.jobs
  end
end
