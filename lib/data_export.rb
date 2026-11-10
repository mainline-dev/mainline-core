# frozen_string_literal: true

require 'json'

module DataExport
  ENTITY_TYPE_NAMES = {
    'storie' => 'story', 'activitie' => 'activity', 'persona' => 'persona',
    'task' => 'task', 'map' => 'map', 'release_slice' => 'release_slice'
  }.freeze

  def self.call(team_id:)
    DB.transaction do
      # set_config(..., is_local: true) is a no-op outside a transaction,
      # so the context must be set inside this block.
      SetTeamContext.call(team_id)
      export(team_id)
    end
  end

  def self.export(team_id)
    team = Team[team_id]
    maps = Map.where(team_id: team_id).all
    map_ids = maps.map(&:id)

    {
      team:           { id: team.id, name: team.name, created_at: team.created_at },
      members:        team_members(team_id),
      maps:           maps.map { |m| { id: m.id, name: m.name, position: m.position, archived_at: m.archived_at } },
      activities:     activities(map_ids),
      tasks:          tasks(map_ids),
      stories:        stories(map_ids),
      personas:       personas(map_ids),
      release_slices: release_slices(map_ids),
      museum_items:   museum_items(team_id),
      events:         events(team_id)
    }
  end

  def self.to_json(team_id:)
    JSON.pretty_generate(call(team_id: team_id))
  end

  def self.team_members(team_id)
    TeamMembership.where(team_id: team_id).all.map { |m|
      person = Person[m.person_id]
      { person_id: m.person_id, name: person.name, working: m.working, left_at: m.left_at }
    }
  end

  def self.activities(map_ids)
    return [] if map_ids.empty?

    Activity.where(map_id: map_ids).all.map { |a|
      { id: a.id, map_id: a.map_id, name: a.name, position: a.position, archived_at: a.archived_at }
    }
  end

  def self.tasks(map_ids)
    return [] if map_ids.empty?

    Task.where(map_id: map_ids).all.map { |t|
      { id: t.id, map_id: t.map_id, activity_id: t.activity_id, name: t.name, position: t.position, archived_at: t.archived_at }
    }
  end

  def self.stories(map_ids)
    return [] if map_ids.empty?

    Story.where(map_id: map_ids).all.map { |s|
      assignments = StoryAssignment.where(story_id: s.id).all.map { |sa|
        { person_id: sa.person_id, assigned_at: sa.assigned_at }
      }
      { id: s.id, map_id: s.map_id, task_id: s.task_id, title: s.title, description: s.description, status: s.status,
        position: s.position, archived_at: s.archived_at, release_slice_id: s.release_slice_id,
        split_from_id: s.split_from_id, created_at: s.created_at,
        deploy_count: s.deploy_count, first_deployed_at: s.first_deployed_at, last_deployed_at: s.last_deployed_at,
        released_at: s.released_at, decoupling_strategy: s.decoupling_strategy, decoupling_label: s.decoupling_label,
        agent_assisted: s.agent_assisted, scenarios: scenarios(s.id), assignments: assignments }
    }
  end

  def self.scenarios(story_id)
    Scenario.where(story_id: story_id).order(:position).all.map { |sc|
      { id: sc.id, name: sc.name, given: sc.given_text, when: sc.when_text, then: sc.then_text,
        position: sc.position, done_at: sc.done_at }
    }
  end

  # The Ticket Museum: every exhibit as it came from Jira, and what became of it.
  def self.museum_items(team_id)
    MuseumItem.where(team_id: team_id).order(:source_key).all.map { |item|
      { id: item.id, source_key: item.source_key, issue_type: item.issue_type, summary: item.summary,
        description: item.description, labels: item.labels, comments: item.comments, links: item.links,
        parent_key: item.parent_key, source_created_at: item.source_created_at,
        source_updated_at: item.source_updated_at, story_id: item.story_id, promoted_at: item.promoted_at,
        discarded_at: item.discarded_at, storage_note: item.storage_note, kept_at: item.kept_at }
    }
  end

  def self.personas(map_ids)
    return [] if map_ids.empty?

    Persona.where(map_id: map_ids).all.map { |p|
      { id: p.id, map_id: p.map_id, name: p.name, position: p.position, archived_at: p.archived_at }
    }
  end

  def self.release_slices(map_ids)
    return [] if map_ids.empty?

    ReleaseSlice.where(map_id: map_ids).all.map { |rs|
      { id: rs.id, map_id: rs.map_id, name: rs.name, position: rs.position, archived_at: rs.archived_at }
    }
  end

  def self.events(team_id)
    Event.where(team_id: team_id).order(:occurred_at).all.map { |e|
      { id: e.id, map_id: e.map_id, actor_id: e.actor_id, occurred_at: e.occurred_at,
        entity_type: ENTITY_TYPE_NAMES.fetch(e.entity_type, e.entity_type),
        entity_id: e.entity_id, action: e.action,
        before_state: e.before_state, after_state: e.after_state }
    }
  end

  private_class_method :team_members, :activities, :tasks, :stories, :scenarios, :personas, :release_slices,
    :museum_items, :events
end
