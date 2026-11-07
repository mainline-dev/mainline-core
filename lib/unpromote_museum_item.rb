# frozen_string_literal: true

require_relative 'archive_story'
require_relative 'record_event'

# Sends a promoted exhibit back to the museum. Its story is archived too when
# nothing has happened to it since the promote: still planned, never deployed,
# nobody assigned, no other exhibit in it, and no event since. Otherwise the
# story stays on its map and only the link goes.
module UnpromoteMuseumItem
  Result = Struct.new(:success?, :errors, :story_archived, keyword_init: true)

  def self.call(item:, actor:)
    DB.transaction do
      item = MuseumItem.where(id: item.id).for_update.first
      next Result.new(success?: false, errors: ['This exhibit has not been promoted']) unless item.promoted_at

      story = item.story
      untouched = untouched?(item, story)
      item.update(story_id: nil, promoted_at: nil, promoted_events: nil)
      archived = untouched && ArchiveStory.call(story: story, actor: actor).success?
      RecordEvent.call(actor_id: actor.id, entity: item, action: 'unpromoted',
        after_state: { source_key: item.source_key, story_id: story.id, story_archived: archived })
      Result.new(success?: true, errors: [], story_archived: archived)
    end
  end

  def self.untouched?(item, story)
    story.status == 'planned' && story.deploy_count.zero? && story.archived_at.nil? &&
      StoryAssignment.where(story_id: story.id).empty? &&
      MuseumItem.where(story_id: story.id).exclude(id: item.id).empty? &&
      Event.where(entity_id: story.id).count == item.promoted_events
  end
  private_class_method :untouched?
end
