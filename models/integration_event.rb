# frozen_string_literal: true

class IntegrationEvent < Sequel::Model
  many_to_one :monitored_repo
  many_to_one :tracked_branch
end
