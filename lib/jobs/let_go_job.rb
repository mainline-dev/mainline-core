# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/api'
require_relative '../bypass_rls'
require_relative '../let_go'

# The curator looks for exhibits worth letting go: in one team's museum after
# an acquisition, and every night in every museum, one museum at a time so one
# that fails holds up nobody else.
class LetGoJob
  include Sidekiq::Job

  INTERVAL = 24 * 60 * 60

  sidekiq_options retry: 3, queue: 'default'

  def perform(team_id = nil)
    return BypassRLS.call { LetGo.detect(team_id: team_id) } if team_id

    BypassRLS.call { MuseumItem.distinct.select_map(:team_id) }.each do |id|
      BypassRLS.call { LetGo.detect(team_id: id) }
    rescue StandardError => e
      warn "LetGoJob: team #{id} skipped: #{e.class}: #{e.message}"
    end
    self.class.perform_in(INTERVAL)
  end

  # Waiting to run, or waiting to be retried after a failure: either would
  # start a second chain beside the one enqueued at startup.
  def self.clear_scheduled
    [Sidekiq::ScheduledSet.new, Sidekiq::RetrySet.new].each do |set|
      set.select { |entry| entry.item['class'] == name && entry.args.empty? }.each(&:delete)
    end
  end
end

Sidekiq.configure_server do |config|
  config.on(:startup) do
    LetGoJob.clear_scheduled
    LetGoJob.perform_async
  end
end
