# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/api'
require_relative '../bypass_rls'
require_relative '../remove_unverified_accounts'

# Every day, remove email signups left unverified for over a week, logging how
# many (never who).
class RemoveUnverifiedAccountsJob
  include Sidekiq::Job

  INTERVAL = 24 * 60 * 60
  UNVERIFIED_FOR = 7 * 24 * 60 * 60

  sidekiq_options retry: 3, queue: 'default'

  def perform
    removed = BypassRLS.call { RemoveUnverifiedAccounts.call(before: Time.now - UNVERIFIED_FOR) }
    warn "RemoveUnverifiedAccounts: removed #{removed} email signups left unverified for over a week"
    self.class.perform_in(INTERVAL)
  end

  # Waiting to run, or waiting to be retried after a failure: either would
  # start a second chain beside the one enqueued at startup.
  def self.clear_scheduled
    [Sidekiq::ScheduledSet.new, Sidekiq::RetrySet.new].each do |set|
      set.select { |entry| entry.item['class'] == name }.each(&:delete)
    end
  end
end

Sidekiq.configure_server do |config|
  config.on(:startup) do
    RemoveUnverifiedAccountsJob.clear_scheduled
    RemoveUnverifiedAccountsJob.perform_async
  end
end
