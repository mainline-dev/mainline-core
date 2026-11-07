# frozen_string_literal: true

require_relative '../model_spec_helper'
require 'sidekiq'
require 'sidekiq/testing'
require_relative '../../lib/jobs/clear_stale_uploads_job'

describe ClearStaleUploadsJob do
  before do
    Sidekiq::Testing.fake!
    Sidekiq::Queues.clear_all
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
  end

  after do
    Sidekiq::Testing.disable!
  end

  def upload(team, status: 'staged', age: 0)
    BypassRLS.call do
      MuseumImport.create(team_id: team.id, actor_id: @person.actor_id, file_name: 'jira.csv', status: status,
        items: Sequel.pg_jsonb([{ source_key: 'SHOP-1' }]), created_at: Time.now - age)
    end
  end

  it "cancels uploads left at the preview for over a day, in every team's museum" do
    day = 24 * 60 * 60
    stale = [upload(Team.create(name: 'Acme'), age: day + 60), upload(Team.create(name: 'Other'), age: day + 60)]
    fresh = upload(Team.create(name: 'Fresh'), age: day - 60)
    imported = upload(Team.create(name: 'Done'), status: 'imported', age: 2 * day)

    ClearStaleUploadsJob.new.perform

    BypassRLS.call do
      stale_states = stale.map { |import| import.refresh.values.values_at(:status, :items) }

      assert_equal [['cancelled', nil]] * 2, stale_states
      assert_equal %w[staged imported], [fresh.refresh.status, imported.refresh.status]
    end
  end

  it 're-enqueues itself after performing' do
    ClearStaleUploadsJob.new.perform

    assert_equal 1, ClearStaleUploadsJob.jobs.size
    assert_in_delta ClearStaleUploadsJob::INTERVAL, ClearStaleUploadsJob.jobs.first['at'] - Time.now.to_f, 60
  end
end
