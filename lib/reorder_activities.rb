# frozen_string_literal: true

require 'securerandom'
require_relative 'rebalance_positions'

module ReorderActivities
  def self.call(map:, activity_ids:, actor:)
    activities = Activity.where(id: activity_ids, map_id: map.id, archived_at: nil).all
    return :not_found unless activities.size == activity_ids.size

    DB.transaction do
      RebalancePositions.reorder(
        table: :activities, records: activities, ordered_ids: activity_ids,
        moved_ids: activity_ids, actor: actor, correlation_id: SecureRandom.uuid
      )
    end

    nil
  end
end
