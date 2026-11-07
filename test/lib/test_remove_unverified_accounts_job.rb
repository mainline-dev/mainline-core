# frozen_string_literal: true

require_relative '../model_spec_helper'
require 'sidekiq'
require 'sidekiq/testing'
require_relative '../../lib/jobs/remove_unverified_accounts_job'

describe RemoveUnverifiedAccountsJob do
  before do
    Sidekiq::Testing.fake!
    Sidekiq::Queues.clear_all
  end

  after do
    Sidekiq::Testing.disable!
  end

  def signup(email, days_ago:)
    person = Person.create(name: 'Test', email: email)
    person.this.update(created_at: Time.now - (days_ago * 24 * 60 * 60))
    PersonIdentity.create(person_id: person.id, provider: 'email', provider_subject: "email-#{email}", email: email)
    person
  end

  it 'removes email signups left unverified for over a week' do
    old = signup('old@acme.co', days_ago: 8)
    fresh = signup('fresh@acme.co', days_ago: 6)

    RemoveUnverifiedAccountsJob.new.perform

    assert_nil Person[old.id]
    refute_nil Person[fresh.id]
  end

  it 'logs how many accounts it removed, and no addresses' do
    signup('old@acme.co', days_ago: 8)

    _out, err = capture_io { RemoveUnverifiedAccountsJob.new.perform }

    assert_match(/removed 1 /, err)
    refute_match(/old@acme\.co/, err)
  end

  it 're-enqueues itself for the next day' do
    RemoveUnverifiedAccountsJob.new.perform

    assert_equal 1, RemoveUnverifiedAccountsJob.jobs.size
    assert_in_delta RemoveUnverifiedAccountsJob::INTERVAL, RemoveUnverifiedAccountsJob.jobs.first['at'] - Time.now.to_f, 60
  end
end
