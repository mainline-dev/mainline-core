# frozen_string_literal: true

require_relative '../../../lib/let_go'
require_relative '../../../lib/unpromote_museum_item'

# What a driver sets up and looks up straight in the test database: the team
# and its people, a map to work on, what a page created, the events recorded,
# and the museum's records. Shared by the HTTP and browser drivers, which both
# reach the test database; the DSL itself never does.
module Records
  def create_team(name)
    team = Team.create(name: name)
    SetTeamContext.call(team.id)
    team
  end

  def suspend_team(team, message:, link:)
    team.update(suspended_at: Time.now, suspended_message: message, suspended_link: link)
  end

  def add_person(team, name:, email:)
    person = Person.create(name: name, email: email, email_verified_at: Time.now)
    TeamMembership.create(team_id: team.id, person_id: person.id)
    person
  end

  def create_map(team, name:)
    SetTeamContext.call(team.id)
    next_pos = (Map.where(team_id: team.id).max(:position) || 0) + 1000
    Map.create(team_id: team.id, name: name, position: next_pos)
  end

  def persona_named(map, name)
    Persona.where(map_id: map.id, name: name).first
  end

  def activity_named(map, name)
    Activity.where(map_id: map.id, name: name).first
  end

  def personas_of(activity)
    ActivityPersona.where(activity_id: activity.id).count
  end

  def task_named(activity, name)
    Task.where(activity_id: activity.id, name: name).first
  end

  def task_of(story)
    Task[story.task_id]
  end

  def story_under(task, title)
    Story.where(task_id: task.id, title: title).first
  end

  def release_slice_named(map, name)
    ReleaseSlice.where(map_id: map.id, name: name).first
  end

  def event_count
    Event.count
  end

  # The events recorded for an entity, in order, all of them or one action's.
  def events_of(entity, action: nil)
    events = Event.where(entity_id: entity.id)
    events = events.where(action: action) if action
    events.order(:event_no).all
  end

  def add_story_note(story, team, note_type:)
    StoryNote.create(story_id: story.id, team_id: team.id, note_type: note_type)
  end

  def dismiss_story_note(note, person)
    note.update(dismissed_at: Time.now, dismissed_by: person.id)
  end

  def museum_item(team, key)
    MuseumItem.where(team_id: team.id, source_key: key).first
  end

  def last_museum_import(team)
    MuseumImport.where(team_id: team.id, status: 'imported').order(:imported_at).last
  end

  def story_titled(team, title)
    Story.where(team_id: team.id, title: title).first
  end

  def story_exhibits(team, title)
    MuseumItem.where(story_id: Story.where(team_id: team.id, title: title).select(:id)).count
  end

  def story_scenarios(team, title)
    story_titled(team, title).scenarios.map { |s| [s.given_text, s.when_text, s.then_text] }
  end

  # An exhibit in some other team's museum.
  def other_team_museum_item
    BypassRLS.call do
      team = Team.create(name: 'Other')
      MuseumItem.create(team_id: team.id, source_key: 'THEM-1', issue_type: 'Story', summary: 'Not yours')
    end
  end

  def let_the_curator_look(team)
    LetGo.detect(team_id: team.id)
  end

  def unpromote_museum_item(item, actor)
    UnpromoteMuseumItem.call(item: item, actor: actor)
  end
end
