# frozen_string_literal: true

require 'securerandom'
require_relative 'record_event'

# Sets a Ticket Museum item aside, or brings it back. A discarded item leaves
# the list and later imports leave it alone, and may carry a note saying why.
# Promoted items are not discarded. Items sent together are a batch: their
# storage events share an id, and they can be brought back as one.
module DiscardMuseumItem
  Result = Struct.new(:success?, :errors, keyword_init: true)
  Outcome = Struct.new(:stored, :batch, keyword_init: true)

  def self.call(item:, actor:, note: nil, batch: nil)
    change(item, actor, 'discarded', note, batch) { |locked|
      if locked.promoted_at
        'A promoted exhibit cannot be sent to storage'
      elsif locked.discarded_at
        'This exhibit is already in storage'
      end
    }
  end

  # Sends each of the items that can go to storage, together, as one batch.
  def self.many(items:, actor:, notes: {})
    batch = SecureRandom.uuid
    stored = DB.transaction {
      items.count { |item| call(item: item, actor: actor, note: notes[item.id], batch: batch).success? }
    }
    Outcome.new(stored: stored, batch: batch)
  end

  # Brings back what is still in storage from a batch; returns how many came back.
  def self.restore_batch(team_id:, actor:, batch:)
    return 0 unless batch

    ids = Event.where(team_id: team_id, correlation_id: batch, action: 'discarded').select_map(:entity_id)
    items = MuseumItem.where(team_id: team_id, id: ids).exclude(discarded_at: nil).all
    DB.transaction { items.count { |item| restore(item: item, actor: actor).success? } }
  end

  def self.restore(item:, actor:)
    change(item, actor, 'restored') { |locked| 'This exhibit is not in storage' unless locked.discarded_at }
  end

  def self.change(item, actor, action, note = nil, batch = nil)
    DB.transaction do
      locked = MuseumItem.where(id: item.id).for_update.first
      error = yield(locked)
      next Result.new(success?: false, errors: [error]) if error

      locked.update(discarded_at: action == 'discarded' ? Time.now : nil, storage_note: note)
      RecordEvent.call(actor_id: actor.id, entity: locked, action: action, after_state: { source_key: locked.source_key },
        correlation_id: batch)
      Result.new(success?: true, errors: [])
    end
  end
  private_class_method :change
end
