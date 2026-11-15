# frozen_string_literal: true

require_relative 'record_walkthrough'

module SoloLog
  Entry = Struct.new(:story_id, :story_title, :person_name, :released_at, :walked_with, keyword_init: true)

  def self.call(team_id:, days: 180)
    cutoff = Time.now - (days * 86_400)
    collab_events = events_since(team_id, 'collaboration_changed', cutoff).group_by(&:entity_id)
    released_at_map = events_since(team_id, 'released', cutoff).to_h { |e| [e.entity_id, e.occurred_at] }

    solo_story_ids = released_at_map.keys.select { |story_id| ended_solo?(collab_events[story_id]) }
    solo_events = collab_events.slice(*solo_story_ids)

    entries(solo_story_ids, solo_events, released_at_map).sort_by(&:released_at).reverse
  end

  def self.events_since(team_id, action, cutoff)
    Event.where(team_id: team_id, action: action).where { occurred_at >= cutoff }.all
  end

  def self.ended_solo?(events)
    last_event = (events || []).max_by(&:event_no)
    last_event&.after_state&.dig('mode') == 'solo'
  end

  def self.entries(story_ids, solo_events, released_at_map)
    stories = Story.where(id: story_ids).to_hash(:id)
    person_ids = solo_events.values.flatten.filter_map { |e| e.after_state['solo_person_id'] }.uniq
    people = Person.where(id: person_ids).to_hash(:id)
    walked_with = walked_with(story_ids)

    story_ids.map { |story_id|
      solo_event = solo_events.fetch(story_id, []).detect { |e| e.after_state['mode'] == 'solo' }
      person_id = solo_event&.after_state&.dig('solo_person_id')

      Entry.new(
        story_id:    story_id,
        story_title: stories[story_id]&.title || '(deleted)',
        person_name: people[person_id]&.name || '?',
        released_at: released_at_map[story_id],
        walked_with: walked_with[story_id]
      )
    }
  end

  # Who each of these stories was walked through with, by name.
  def self.walked_with(story_ids)
    walks = Event.where(entity_id: story_ids, action: RecordWalkthrough::ACTION).all
    attending = walks.group_by(&:entity_id).transform_values { |story_walks|
      story_walks.flat_map { |walk| walk.after_state['attendee_ids'].to_a }
    }
    people = Person.where(id: attending.values.flatten).order(:name).all
    story_ids.to_h { |story_id|
      [story_id, people.select { |person| attending.fetch(story_id, []).include?(person.id) }]
    }
  end

  private_class_method :events_since, :ended_solo?, :entries, :walked_with
end
