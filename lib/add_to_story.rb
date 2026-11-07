# frozen_string_literal: true

require 'securerandom'
require_relative 'record_event'
require_relative 'unpromote_museum_item'

# Adds Ticket Museum items to a story already on a map. The items are linked and
# the story is left exactly as it was: a story carries nothing from Jira. Several
# go together or not at all, and what went together can be sent back together.
# An item added this way has no promote to undo, so sending it back never
# archives the story.
module AddToStory
  Result = Struct.new(:success?, :errors, :story, :batch, keyword_init: true)

  def self.call(items:, story_id:, team:, actor:)
    DB.transaction do
      locked = MuseumItem.where(id: items.map(&:id)).order(:id).for_update.all
      story = Story.where(id: story_id, team_id: team.id, archived_at: nil).first
      error = refusal(locked, story)
      next Result.new(success?: false, errors: [error]) if error

      batch = SecureRandom.uuid
      locked.each { |item| link(item, story, actor, batch) }
      Result.new(success?: true, errors: [], story: story, batch: batch)
    end
  end

  # Sends back what was added together; returns how many went back.
  def self.undo(team_id:, actor:, batch:)
    ids = Event.where(team_id: team_id, correlation_id: batch, action: 'added_to_story').select_map(:entity_id)
    items = MuseumItem.where(team_id: team_id, id: ids).exclude(promoted_at: nil).all
    DB.transaction { items.count { |item| UnpromoteMuseumItem.call(item: item, actor: actor).success? } }
  end

  def self.link(item, story, actor, batch)
    item.update(story_id: story.id, promoted_at: Time.now)
    RecordEvent.call(actor_id: actor.id, entity: item, action: 'added_to_story', correlation_id: batch,
      after_state: { source_key: item.source_key, story_id: story.id })
  end

  def self.refusal(items, story)
    if items.empty?
      'Choose an exhibit to add'
    elsif !story
      'Choose a story on one of your maps'
    elsif !items.all?(&:promotable?)
      'That exhibit can no longer be added to a story'
    end
  end
  private_class_method :link, :refusal
end
