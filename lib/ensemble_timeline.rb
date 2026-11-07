# frozen_string_literal: true

module EnsembleTimeline
  Session = Struct.new(:story_id, :story_title, :person_names, :occurred_at, :assignment_count, keyword_init: true)

  ONE_DAY = 86_400

  def self.call(team_id:, days: 30)
    events = ensemble_events(team_id, Time.now - (days * ONE_DAY))
    stories = Story.where(id: events.map(&:entity_id).uniq).to_hash(:id)
    people = Person.where(id: events.flat_map { |e| person_ids(e) }.uniq).to_hash(:id)

    events.map { |e| session_for(e, stories, people) }
  end

  def self.ensemble_events(team_id, cutoff)
    Event
      .where(team_id: team_id, action: 'collaboration_changed')
      .where { occurred_at >= cutoff }
      .order(Sequel.desc(:occurred_at))
      .all
      .select { |e| e.after_state['mode'] == 'ensemble' }
  end

  def self.person_ids(event)
    event.after_state['person_ids'] || []
  end

  def self.session_for(event, stories, people)
    Session.new(
      story_id:         event.entity_id,
      story_title:      stories[event.entity_id]&.title || '(deleted)',
      person_names:     person_ids(event).map { |pid| people[pid]&.name || '?' },
      occurred_at:      event.occurred_at,
      assignment_count: event.after_state['assignment_count']
    )
  end

  private_class_method :ensemble_events, :person_ids, :session_for
end
