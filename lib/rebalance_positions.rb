# frozen_string_literal: true

require_relative 'record_event'

module RebalancePositions
  GAP = 1000

  def self.position_at(index)
    (index + 1) * GAP
  end

  # Vacate to temporary negative positions before assigning final ones;
  # in-place assignment trips the unique position indexes.
  def self.assign(table, current_ids, ordered_ids)
    current_ids.each_with_index { |id, i| DB[table].where(id: id).update(position: -(i + 1)) }
    ordered_ids.each_with_index { |id, i| DB[table].where(id: id).update(position: position_at(i)) }
  end

  # Call inside a DB.transaction block. Records a 'reordered' event for each
  # moved record whose position changed.
  def self.reorder(table:, records:, ordered_ids:, moved_ids:, actor:, correlation_id:)
    old_positions = records.to_h { |r| [r.id, r.position] }
    by_id = records.to_h { |r| [r.id, r] }
    assign(table, records.map(&:id), ordered_ids)

    moved_ids.each do |id|
      new_pos = position_at(ordered_ids.index(id))
      next if old_positions[id] == new_pos

      RecordEvent.call(
        actor_id: actor.id, entity: by_id[id].refresh, action: 'reordered',
        before_state: { position: old_positions[id] },
        after_state: { position: new_pos },
        correlation_id: correlation_id
      )
    end
  end
end
