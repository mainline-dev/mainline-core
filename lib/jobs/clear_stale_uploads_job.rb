# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/api'
require_relative '../bypass_rls'
require_relative '../import_to_museum'

# Every hour, cancel Ticket Museum uploads left at the preview for over a day,
# so their staged items do not sit in the database.
class ClearStaleUploadsJob
  include Sidekiq::Job

  INTERVAL = 60 * 60

  sidekiq_options retry: 3, queue: 'default'

  def perform
    BypassRLS.call { ImportToMuseum.clear_stale(before: Time.now - ImportToMuseum::STALE_AFTER) }
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
    ClearStaleUploadsJob.clear_scheduled
    ClearStaleUploadsJob.perform_async
  end
end
